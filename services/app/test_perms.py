"""Dev-only checks for the permissions store: cd services/app && python -m pytest test_perms.py -q

The store runs on sqlite3 here (the same SQL as Postgres), so nothing needs a database server.
"""

import sqlite3

import pytest
from flask import Flask

import admin
import auth
import perms


ADMIN = "admin@example.com"
MEMBER = "member@example.com"
STRANGER = "stranger@example.com"
PERMS_ENV = ("SITE_DATABASE_URL", "SITE_ADMIN_EMAILS", "SITE_MEMBER_EMAILS", "SITE_EVERYONE")


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    for name in PERMS_ENV:
        monkeypatch.delenv(name, raising=False)


@pytest.fixture
def conn():
    conn = sqlite3.connect(":memory:")
    perms.create_tables(conn)
    perms.seed(conn, [ADMIN], [MEMBER], ["site", "strelitzia"])
    yield conn
    conn.close()


def test_pages_in_column_order():
    assert perms.PAGE_KEYS == ("site", "strelitzia", "bracket")
    assert perms.page("strelitzia").cap and perms.page("strelitzia").needs_account
    with pytest.raises(perms.PermsError):
        perms.page("nope")


def test_admin_gets_everything_without_cap(conn):
    access = perms.access_for(conn, "Admin@Example.com ")
    assert access.admin is True
    assert access.pages == frozenset(perms.PAGE_KEYS)
    assert access.cap_usd is None


def test_member_gets_grants_and_cap(conn):
    access = perms.access_for(conn, MEMBER)
    assert access.admin is False
    assert access.pages == frozenset(perms.PAGE_KEYS)
    assert access.cap_usd == 5.0


def test_strangers_get_everyone_row_without_account_pages(conn):
    # The seed already drops needs_account pages from the everyone row; a hand-edited row is stripped on read too.
    perms._run(conn, "INSERT INTO site_grants (email, page) VALUES ('*', 'strelitzia')")
    for email in (None, STRANGER, "*"):
        access = perms.access_for(conn, email)
        assert access.admin is False
        assert access.pages == {"site"}
        assert access.cap_usd is None


def test_invite_starts_from_everyone_row(conn):
    perms.set_grant(conn, "*", "bracket", True)
    row = perms.invite(conn, " New@Example.com")
    assert row.to_dict() == {"email": "new@example.com", "admin": False, "pages": ["site", "bracket"], "cap_usd": 5.0}
    perms.set_cap(conn, "new@example.com", 9)
    assert perms.invite(conn, "new@example.com").cap_usd == 9.0  # idempotent: doesn't reset
    with pytest.raises(perms.PermsError):
        perms.invite(conn, "not an email")
    with pytest.raises(perms.PermsError):
        perms.invite(conn, "*")


def test_new_cap_page_grant_starts_at_default_cap(conn):
    perms.invite(conn, STRANGER)
    perms.set_cap(conn, STRANGER, None)
    assert perms.access_for(conn, STRANGER).cap_usd is None
    row = perms.set_grant(conn, STRANGER, "strelitzia", True)
    assert "strelitzia" in row.pages and row.cap_usd == 5.0
    row = perms.set_grant(conn, STRANGER, "strelitzia", False)
    assert row.pages == ["site"]


def test_guards(conn):
    with pytest.raises(perms.PermsError, match="unknown page"):
        perms.set_grant(conn, MEMBER, "nope", True)
    with pytest.raises(perms.PermsError, match="last admin"):
        perms.set_admin(conn, ADMIN, False)
    with pytest.raises(perms.PermsError, match="last admin"):
        perms.remove(conn, ADMIN)
    with pytest.raises(perms.PermsError, match="needs an account"):
        perms.set_grant(conn, "*", "strelitzia", True)
    with pytest.raises(perms.PermsError):
        perms.set_cap(conn, "*", 5)
    with pytest.raises(perms.PermsError):
        perms.set_admin(conn, "*", True)
    with pytest.raises(perms.PermsError):
        perms.remove(conn, "*")
    with pytest.raises(perms.NotFound):
        perms.set_cap(conn, STRANGER, 1)
    for bad in (-1, float("nan"), True, "5"):
        with pytest.raises(perms.PermsError):
            perms.set_cap(conn, MEMBER, bad)


def test_second_admin_can_be_demoted_and_removed(conn):
    perms.set_admin(conn, MEMBER, True)
    assert perms.access_for(conn, MEMBER).admin is True
    perms.set_admin(conn, ADMIN, False)
    assert perms.access_for(conn, ADMIN).admin is False
    perms.set_admin(conn, ADMIN, True)
    perms.remove(conn, MEMBER)
    assert perms.get_row(conn, MEMBER) is None
    assert perms.access_for(conn, MEMBER).pages == {"site"}
    assert [r.email for r in perms.list_rows(conn)] == [ADMIN]


def test_demoted_admin_gets_default_cap(conn):
    perms.set_admin(conn, MEMBER, True)
    row = perms.set_admin(conn, ADMIN, False)
    assert row.cap_usd == 5.0
    assert perms.access_for(conn, ADMIN).cap_usd == 5.0


def test_no_admin_left_lets_env_admins_back_in(conn, monkeypatch):
    perms._run(conn, "UPDATE site_users SET admin = ?", (False,))  # what a race past the guard would leave
    monkeypatch.setenv("SITE_ADMIN_EMAILS", ADMIN)
    assert perms.access_for(conn, ADMIN).admin is True
    assert perms.access_for(conn, MEMBER).pages == frozenset(perms.PAGE_KEYS)  # the DB still decides for the rest
    assert perms.access_for(conn, STRANGER).pages == {"site"}
    monkeypatch.setenv("SITE_EVERYONE", "")
    perms.set_grant(conn, "*", "site", False)
    assert perms.access_for(conn, STRANGER).pages == frozenset()
    monkeypatch.delenv("SITE_ADMIN_EMAILS")
    assert perms.access_for(conn, STRANGER).pages == {"site"}  # anti-lockout


@pytest.mark.parametrize("email, ok", [
    ("a@b.co", True), ("a@b", False), ("@b.co", False), ("a@b@c.co", False), ("a@b.co,c@d.co", False),
    ("a b@c.co", False),
])
def test_looks_like_email(email, ok):
    assert perms.looks_like_email(email) is ok


def test_seed_only_on_empty_db(conn):
    assert perms.seed(conn, ["other@example.com"], [], ["site", "bracket"]) is None
    assert perms.get_row(conn, "other@example.com") is None
    assert perms.everyone(conn).pages == ["site"]


def test_seed_writes_admins_members_and_everyone():
    conn = sqlite3.connect(":memory:")
    perms.create_tables(conn)
    counts = perms.seed(conn, [ADMIN, ADMIN, "typo@gmail"], [MEMBER, ADMIN], [])
    assert counts == {"admins": 1, "members": 1, "everyone_pages": 0}
    assert [r.email for r in perms.list_rows(conn)] == [ADMIN, MEMBER]
    assert perms.access_for(conn, STRANGER).pages == frozenset()


def test_seed_waits_for_admins():
    conn = sqlite3.connect(":memory:")
    perms.create_tables(conn)
    assert perms.seed(conn, [], [MEMBER], ["site"]) is None
    assert perms.seed(conn, [ADMIN], [MEMBER], ["site"]) is not None


def test_env_only_mode(monkeypatch):
    monkeypatch.setenv("SITE_ADMIN_EMAILS", f"{ADMIN.upper()}, other@example.com")
    monkeypatch.setenv("SITE_EVERYONE", "site,strelitzia,bogus")
    assert perms.connect() is None
    assert perms.access_for(None, ADMIN).admin is True
    assert perms.access_for(None, ADMIN).pages == frozenset(perms.PAGE_KEYS)
    assert perms.access_for(None, STRANGER).pages == {"site"}
    assert perms.access_for(None, None).pages == {"site"}
    assert [r.email for r in perms.list_rows(None)] == [ADMIN, "other@example.com"]
    for write in (lambda: perms.invite(None, STRANGER), lambda: perms.set_admin(None, ADMIN, False),
                  lambda: perms.set_grant(None, "*", "site", True), lambda: perms.set_cap(None, ADMIN, 1),
                  lambda: perms.remove(None, ADMIN)):
        with pytest.raises(perms.PermsError, match="no database"):
            write()


def test_env_only_mode_without_site_for_everyone(monkeypatch):
    monkeypatch.setenv("SITE_ADMIN_EMAILS", ADMIN)
    monkeypatch.setenv("SITE_EVERYONE", "")
    assert perms.access_for(None, STRANGER).pages == frozenset()
    assert perms.access_for(None, None).pages == frozenset()


def test_anti_lockout_without_any_admin(monkeypatch):
    monkeypatch.setenv("SITE_EVERYONE", "")
    assert perms.access_for(None, None).pages == {"site"}
    conn = sqlite3.connect(":memory:")
    perms.create_tables(conn)  # an empty DB, before the .env step
    assert perms.access_for(conn, STRANGER).pages == {"site"}
    assert perms.access_for(conn, STRANGER).admin is False


# --- /auth/verify?page=, /auth/me and /api/admin ---

AUTH_ENV = {
    "GOOGLE_CLIENT_ID": "client-id.apps.googleusercontent.com",
    "GOOGLE_CLIENT_SECRET": "client-secret",
    "SITE_SESSION_SECRET": "test-session-secret",
    "PUBLIC_URL": "https://preprod.engineerfamily.net",
}


def make_site(monkeypatch, tmp_path, env=None, db=True):
    """auth + perms + admin on a sqlite file DB (or env-only with db=False), seeded from SITE_* like the real app."""
    for name, value in {**AUTH_ENV, "SITE_ADMIN_EMAILS": ADMIN, "SITE_MEMBER_EMAILS": MEMBER, "SITE_EVERYONE": "site",
                        **(env or {})}.items():
        monkeypatch.setenv(name, value)
    app = Flask(__name__)
    if db:
        path = tmp_path / "site.db"
        app.config["PERMS_CONNECT"] = lambda: sqlite3.connect(path)
    else:
        app.config["PERMS_CONNECT"] = lambda: None
    auth.init_app(app)
    perms.init_app(app)
    admin.init_app(app)
    return app


def sign_in(client, email):
    with client.session_transaction() as sess:
        sess["sub"] = "sub-" + email
        sess["email"] = email
        sess["name"] = "Test"


@pytest.fixture
def site(monkeypatch, tmp_path):
    return make_site(monkeypatch, tmp_path)


def as_(site, email=None):
    client = site.test_client()
    if email:
        sign_in(client, email)
    return client


def test_startup_seeds_and_me_reports_access(site):
    assert as_(site).get("/auth/me").get_json()["pages"] == ["site"]
    me = as_(site, ADMIN).get("/auth/me").get_json()
    assert me["admin"] is True and me["pages"] == ["site", "strelitzia", "bracket"]
    me = as_(site, STRANGER).get("/auth/me").get_json()
    assert me["admin"] is False and me["pages"] == ["site"]


def test_verify_without_page_is_unchanged(site):
    resp = as_(site).get("/auth/verify")
    assert resp.status_code == 204
    assert not [h for h in resp.headers.keys() if h.lower().startswith("x-auth-request-")]
    assert as_(site, STRANGER).get("/auth/verify").status_code == 204


def test_verify_page_headers(site):
    resp = as_(site, ADMIN).get("/auth/verify?page=strelitzia")
    assert resp.status_code == 204
    assert resp.headers["Cache-Control"] == "no-store"
    assert resp.headers["X-Auth-Request-Email"] == ADMIN
    assert resp.headers["X-Auth-Request-Access"] == "strelitzia"
    assert resp.headers["X-Auth-Request-Admin"] == "1"
    assert resp.headers["X-Auth-Request-Cap-Usd"] == "none"

    resp = as_(site, MEMBER).get("/auth/verify?page=strelitzia")
    assert resp.status_code == 204
    assert resp.headers["X-Auth-Request-Admin"] == "0"
    assert resp.headers["X-Auth-Request-Cap-Usd"] == "5.00"

    resp = as_(site).get("/auth/verify?page=site")
    assert resp.status_code == 204
    assert resp.headers["X-Auth-Request-Access"] == "site"
    assert resp.headers["X-Auth-Request-Admin"] == "0"
    assert "X-Auth-Request-Cap-Usd" not in resp.headers
    assert "X-Auth-Request-Email" not in resp.headers


def test_verify_page_refusals(site):
    assert as_(site, STRANGER).get("/auth/verify?page=strelitzia").status_code == 403
    resp = as_(site).get("/auth/verify?page=strelitzia")
    assert resp.status_code == 401
    assert resp.headers["Cache-Control"] == "no-store"
    assert as_(site).get("/auth/verify?page=bracket").status_code == 401
    assert as_(site, ADMIN).get("/auth/verify?page=nope").status_code == 404


def test_verify_falls_back_to_env_on_db_error(monkeypatch, tmp_path):
    site = make_site(monkeypatch, tmp_path, env={"SITE_EVERYONE": ""})

    def broken():
        raise sqlite3.OperationalError("down")
    site.config["PERMS_CONNECT"] = broken
    assert as_(site, MEMBER).get("/auth/verify?page=strelitzia").status_code == 403  # members live in the DB only
    assert as_(site, MEMBER).get("/auth/verify?page=site").status_code == 403
    assert as_(site, ADMIN).get("/auth/verify?page=strelitzia").status_code == 204
    assert as_(site).get("/auth/verify").status_code == 204


def test_admin_api_needs_an_admin(site):
    assert as_(site).get("/api/admin/users").status_code == 401
    resp = as_(site, STRANGER).get("/api/admin/users")
    assert resp.status_code == 403
    assert resp.headers["Cache-Control"] == "no-store"
    assert as_(site, MEMBER).get("/api/admin/users").status_code == 403
    assert as_(site, MEMBER).post("/api/admin/users", json={"email": STRANGER}).status_code == 403


def test_admin_lists_users(site):
    resp = as_(site, ADMIN).get("/api/admin/users")
    assert resp.status_code == 200
    assert resp.headers["Cache-Control"] == "no-store"
    body = resp.get_json()
    assert body["db"] is True
    assert [p["key"] for p in body["pages"]] == ["site", "strelitzia", "bracket"]
    assert body["pages"][1] == {"key": "strelitzia", "label": "Strelitzia", "cap": True, "needs_account": True}
    assert body["everyone"]["pages"] == ["site"]
    assert body["users"] == [
        {"email": ADMIN, "admin": True, "pages": ["site", "strelitzia", "bracket"], "cap_usd": None},
        {"email": MEMBER, "admin": False, "pages": ["site", "strelitzia", "bracket"], "cap_usd": 5.0},
    ]


def test_admin_invites_changes_and_removes(site):
    client = as_(site, ADMIN)
    resp = client.post("/api/admin/users", json={"email": "New@Example.com"})
    assert resp.status_code == 201
    assert resp.get_json() == {"email": "new@example.com", "admin": False, "pages": ["site"], "cap_usd": 5.0}
    assert client.post("/api/admin/users", json={"email": "new@example.com"}).status_code == 409
    assert client.post("/api/admin/users", json={"email": "nope"}).status_code == 400

    resp = client.patch("/api/admin/users/new@example.com",
                        json={"pages": {"strelitzia": True, "site": False}, "cap_usd": 12.5})
    assert resp.status_code == 200
    assert resp.get_json()["pages"] == ["strelitzia"] and resp.get_json()["cap_usd"] == 12.5
    assert as_(site, "new@example.com").get("/auth/verify?page=strelitzia").headers["X-Auth-Request-Cap-Usd"] == "12.50"
    assert client.patch("/api/admin/users/new@example.com", json={"cap_usd": None}).get_json()["cap_usd"] is None
    assert client.patch("/api/admin/users/new@example.com", json={"admin": True}).get_json()["admin"] is True

    assert client.delete("/api/admin/users/new@example.com", json={}).status_code == 204
    assert client.patch("/api/admin/users/new@example.com", json={"admin": True}).status_code == 404


def test_admin_refusals(site):
    client = as_(site, ADMIN)
    resp = client.patch(f"/api/admin/users/{MEMBER}", json={"pages": {"nope": True}})
    assert resp.status_code == 400 and "unknown page" in resp.get_json()["error"]
    assert client.patch(f"/api/admin/users/{MEMBER}", json={"cap_usd": "lots"}).status_code == 400
    assert client.patch(f"/api/admin/users/{ADMIN}", json={"admin": False}).status_code == 400
    assert client.delete(f"/api/admin/users/{ADMIN}", json={}).status_code == 400
    assert client.patch("/api/admin/users/*", json={"admin": True}).status_code == 400
    # A failed change writes nothing: the valid grant before the bad one is rolled back.
    resp = client.patch(f"/api/admin/users/{MEMBER}", json={"pages": {"site": False}, "cap_usd": -1})
    assert resp.status_code == 400
    assert "site" in client.get("/api/admin/users").get_json()["users"][1]["pages"]


def test_admin_writes_need_json(site):
    client = as_(site, ADMIN)
    assert client.post("/api/admin/users", data={"email": STRANGER}).status_code == 415
    assert client.delete(f"/api/admin/users/{MEMBER}").status_code == 415
    assert client.get("/api/admin/users").status_code == 200


def test_admin_changes_everyone(site):
    client = as_(site, ADMIN)
    resp = client.patch("/api/admin/everyone", json={"pages": {"bracket": True, "site": False}})
    assert resp.status_code == 200
    assert resp.get_json()["pages"] == ["bracket"]
    assert as_(site).get("/auth/verify?page=site").status_code == 401
    assert as_(site).get("/auth/verify?page=bracket").status_code == 204
    resp = client.patch("/api/admin/everyone", json={"pages": {"strelitzia": True}})
    assert resp.status_code == 400 and "needs an account" in resp.get_json()["error"]


def test_admin_api_in_env_only_mode(monkeypatch, tmp_path):
    site = make_site(monkeypatch, tmp_path, db=False)
    client = as_(site, ADMIN)
    body = client.get("/api/admin/users").get_json()
    assert body["db"] is False
    assert [u["email"] for u in body["users"]] == [ADMIN]
    resp = client.post("/api/admin/users", json={"email": STRANGER})
    assert resp.status_code == 400 and resp.get_json()["error"] == "no database"
    assert client.patch("/api/admin/everyone", json={"pages": {"site": True}}).status_code == 400
