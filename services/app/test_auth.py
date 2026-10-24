"""Dev-only checks for the /auth/* blueprint: cd services/app && python -m pytest test_auth.py -q"""

import importlib
from urllib.parse import parse_qs, urlparse

import pytest
from flask import Flask

import auth


ENV = {
    "GOOGLE_CLIENT_ID": "client-id.apps.googleusercontent.com",
    "GOOGLE_CLIENT_SECRET": "client-secret",
    "SITE_SESSION_SECRET": "test-session-secret",
    "PUBLIC_URL": "https://preprod.engineerfamily.net",
}
SITE_ENV = ("SITE_DATABASE_URL", "SITE_ADMIN_EMAILS", "SITE_MEMBER_EMAILS", "SITE_EVERYONE")
ID_INFO = {"sub": "1234567890", "email": "test@example.com", "email_verified": True, "name": "Zoë Test"}


def make_app(monkeypatch, env):
    for name in (*ENV, *SITE_ENV):
        monkeypatch.delenv(name, raising=False)
    for name, value in env.items():
        monkeypatch.setenv(name, value)
    app = Flask(__name__)
    auth.init_app(app)
    return app


@pytest.fixture
def client(monkeypatch):
    return make_app(monkeypatch, ENV).test_client()


@pytest.fixture
def google(monkeypatch):
    """Stub Google: the token exchange returns an ID token, and verifying it returns ID_INFO."""
    calls = {}

    class Response:
        status_code = 200

        def json(self):
            return {"id_token": "signed.id.token"}

    def post(url, timeout, data):
        calls["post"] = data
        return Response()

    def verify(token, request, audience, clock_skew_in_seconds):
        calls["verify"] = (token, audience, clock_skew_in_seconds)
        return dict(ID_INFO)

    monkeypatch.setattr(auth.requests, "post", post)
    monkeypatch.setattr(auth.id_token, "verify_oauth2_token", verify)
    return calls


def start_login(client, next_path="/games/"):
    resp = client.get("/auth/login", query_string={"next": next_path})
    assert resp.status_code == 303
    return parse_qs(urlparse(resp.headers["Location"]).query)


def session_cookie(resp):
    return next(h for h in resp.headers.getlist("Set-Cookie") if h.startswith("ef_session="))


@pytest.mark.parametrize("value, expected", [
    ("/games/", "/games/"),
    ("/strelitzia/dashboard/?tab=jobs", "/strelitzia/dashboard/?tab=jobs"),
    (None, "/"),
    ("", "/"),
    ("games", "/"),
    ("https://evil.com/", "/"),
    ("//evil.com", "/"),
    ("/\\evil.com", "/"),
    ("/\t/evil.com", "/"),
    ("/\n/evil.com", "/"),
])
def test_safe_next(value, expected):
    assert auth.safe_next(value) == expected


def test_login_redirects_to_google(client):
    params = start_login(client)
    assert params["redirect_uri"] == ["https://preprod.engineerfamily.net/auth/callback"]
    assert params["scope"] == ["openid email profile"]
    assert params["prompt"] == ["select_account"]
    assert params["state"][0]


def test_callback_sets_site_cookie(client, google):
    state = start_login(client)["state"][0]
    resp = client.get("/auth/callback", query_string={"state": state, "code": "abc"})
    assert resp.status_code == 303
    assert resp.headers["Location"] == "/games/"
    cookie = session_cookie(resp)
    attrs = [part.strip().lower() for part in cookie.split(";")]
    assert "path=/" in attrs
    assert not any(a.startswith("domain=") for a in attrs)
    assert "httponly" in attrs
    assert "secure" in attrs
    assert "samesite=lax" in attrs
    assert any(a.startswith("expires=") for a in attrs)
    assert google["verify"] == ("signed.id.token", ENV["GOOGLE_CLIENT_ID"], 30)
    assert google["post"]["redirect_uri"] == "https://preprod.engineerfamily.net/auth/callback"
    me = client.get("/auth/me").get_json()
    # No admin anywhere (env-only mode, no SITE_ADMIN_EMAILS): anti-lockout leaves the site open.
    assert me == {"enabled": True, "signed_in": True, "email": "test@example.com", "name": "Zoë Test",
                  "admin": False, "pages": ["site"]}


def test_wrong_state_signs_nobody_in(client, google):
    start_login(client)
    resp = client.get("/auth/callback", query_string={"state": "forged", "code": "abc"})
    assert resp.status_code == 303
    assert resp.headers["Location"] == "/games/?signin=error"
    assert "post" not in google
    assert client.get("/auth/me").get_json()["signed_in"] is False


def test_unverified_email_signs_nobody_in(client, google, monkeypatch):
    monkeypatch.setattr(auth.id_token, "verify_oauth2_token", lambda *a, **k: {**ID_INFO, "email_verified": False})
    state = start_login(client, "/?x=1")["state"][0]
    resp = client.get("/auth/callback", query_string={"state": state, "code": "abc"})
    assert resp.headers["Location"] == "/?x=1&signin=error"
    assert client.get("/auth/me").get_json()["signed_in"] is False


def test_verify_headers_only_with_session(client, google):
    resp = client.get("/auth/verify")
    assert resp.status_code == 204
    assert resp.headers["Cache-Control"] == "no-store"
    assert not [h for h in resp.headers.keys() if h.lower().startswith("x-auth-request-")]

    state = start_login(client)["state"][0]
    client.get("/auth/callback", query_string={"state": state, "code": "abc"})
    resp = client.get("/auth/verify")
    assert resp.status_code == 204
    assert resp.headers["X-Auth-Request-Email"] == "test@example.com"
    assert resp.headers["X-Auth-Request-User"] == "1234567890"
    assert resp.headers["X-Auth-Request-Preferred-Username"] == "Zo%C3%AB%20Test"


def test_logout_clears_session(client, google):
    state = start_login(client)["state"][0]
    client.get("/auth/callback", query_string={"state": state, "code": "abc"})
    resp = client.post("/auth/logout")
    assert resp.status_code == 204
    assert client.get("/auth/me").get_json()["signed_in"] is False
    assert client.get("/auth/logout").status_code == 405


def test_disabled_without_client_id(monkeypatch):
    client = make_app(monkeypatch, {}).test_client()
    assert client.get("/auth/login").status_code == 404
    assert client.get("/auth/callback").status_code == 404
    resp = client.get("/auth/me")
    assert resp.headers["Cache-Control"] == "no-store"
    assert resp.get_json() == {"enabled": False, "signed_in": False, "email": None, "name": None,
                               "admin": False, "pages": ["site"]}
    assert client.get("/auth/verify").status_code == 204


def test_denied_signed_out(client):
    resp = client.get("/auth/denied", query_string={"status": "401"}, headers={"X-Original-URI": "/games/?a=1&b=2"})
    assert resp.status_code == 401
    assert resp.headers["Cache-Control"] == "no-store"
    assert resp.mimetype == "text/html"
    page = resp.get_data(as_text=True)
    assert "Sign in to continue" in page
    assert 'href="/auth/login?next=%2Fgames%2F%3Fa%3D1%26b%3D2"' in page
    assert 'next="/games/?a=1&amp;b=2"' in page
    assert "/shared/site-header.js" in page and "<ef-home" in page


def test_denied_signed_in(client):
    resp = client.get("/auth/denied", query_string={"status": "403", "next": "/strelitzia/dashboard/"})
    assert resp.status_code == 403
    page = resp.get_data(as_text=True)
    assert "You don't have access to this page. Ask an admin." in page
    assert "/auth/login" not in page
    assert 'next="/strelitzia/dashboard/"' in page


@pytest.mark.parametrize("next_path", ["//evil.com/", "https://evil.com/", "/\\evil.com"])
def test_denied_blocks_open_redirect(client, next_path):
    page = client.get("/auth/denied", query_string={"status": "401", "next": next_path}).get_data(as_text=True)
    assert "evil.com" not in page
    assert 'href="/auth/login?next=%2F"' in page


def test_denied_escapes_next(client):
    page = client.get("/auth/denied", query_string={"next": '/x"><script>alert(1)</script>'}).get_data(as_text=True)
    assert "<script>alert" not in page
    assert 'next="/x&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"' in page


@pytest.mark.parametrize("missing", ["GOOGLE_CLIENT_SECRET", "SITE_SESSION_SECRET", "PUBLIC_URL"])
def test_refuses_half_configured(monkeypatch, missing):
    with pytest.raises(RuntimeError, match=missing):
        make_app(monkeypatch, {k: v for k, v in ENV.items() if k != missing})


def test_privacy_page(monkeypatch):
    for name in (*ENV, *SITE_ENV):
        monkeypatch.delenv(name, raising=False)
    site = importlib.import_module("app")
    resp = site.app.test_client().get("/privacy")
    assert resp.status_code == 200
    assert b"Privacy policy" in resp.data
