"""Dev-only checks for the permissions store: cd services/app && python -m pytest test_perms.py -q

The store runs on sqlite3 here (the same SQL as Postgres), so nothing needs a database server.
"""

import sqlite3

import pytest

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


def test_seed_only_on_empty_db(conn):
    assert perms.seed(conn, ["other@example.com"], [], ["site", "bracket"]) is None
    assert perms.get_row(conn, "other@example.com") is None
    assert perms.everyone(conn).pages == ["site"]


def test_seed_writes_admins_members_and_everyone():
    conn = sqlite3.connect(":memory:")
    perms.create_tables(conn)
    counts = perms.seed(conn, [ADMIN, ADMIN], [MEMBER, ADMIN], [])
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
