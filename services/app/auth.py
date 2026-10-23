"""Site-wide Google sign-in at /auth/*.

It only knows who you are (Google `sub`, verified email, name), kept in Flask's signed session cookie `ef_session`:
host-only (no Domain), Path=/, HttpOnly, Secure on https, SameSite=Lax, 30 days. Signing in grants nothing by itself;
`perms` decides which pages a visitor may open (/auth/verify?page=<key>). Off (login 404s, /auth/me says
enabled: false) while GOOGLE_CLIENT_ID is unset.
"""

import logging
import os
import secrets
from datetime import timedelta
from urllib.parse import quote, urlencode

import requests
from flask import Blueprint, abort, current_app, jsonify, redirect, request, session
from google.auth.exceptions import GoogleAuthError
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

import perms


log = logging.getLogger(__name__)

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPES = "openid email profile"
CLOCK_SKEW_SECONDS = 30
SESSION_DAYS = 30
REQUIRED_WITH_CLIENT_ID = ("GOOGLE_CLIENT_SECRET", "SITE_SESSION_SECRET", "PUBLIC_URL")

bp = Blueprint("auth", __name__, url_prefix="/auth")


def init_app(app):
    """Configure the session cookie and register the blueprint. Refuses half-configured sign-in."""
    client_id = os.environ.get("GOOGLE_CLIENT_ID", "").strip()
    if client_id:
        missing = [name for name in REQUIRED_WITH_CLIENT_ID if not os.environ.get(name, "").strip()]
        if missing:
            raise RuntimeError(f"GOOGLE_CLIENT_ID is set but {', '.join(missing)} is not")
    public_url = os.environ.get("PUBLIC_URL", "").strip().rstrip("/")
    # With sign-in off nothing is stored, but the session still needs a key; a per-process one is enough.
    app.secret_key = os.environ.get("SITE_SESSION_SECRET", "").strip() or secrets.token_hex(32)
    app.config.update(
        AUTH_ENABLED=bool(client_id),
        GOOGLE_CLIENT_ID=client_id,
        PUBLIC_URL=public_url,
        SESSION_COOKIE_NAME="ef_session",
        SESSION_COOKIE_PATH="/",
        SESSION_COOKIE_DOMAIN=None,
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SECURE=public_url.startswith("https://"),
        SESSION_COOKIE_SAMESITE="Lax",
        PERMANENT_SESSION_LIFETIME=timedelta(days=SESSION_DAYS),
        # 30 days from sign-in, not rolling: no Set-Cookie on every page and asset response.
        SESSION_REFRESH_EACH_REQUEST=False,
    )
    app.register_blueprint(bp)


def safe_next(value):
    """A same-site path to return to, or "/". Blocks open redirects such as //evil.com and /\\evil.com."""
    if not value or not value.startswith("/") or value.startswith("//"):
        return "/"
    # Browsers treat \ as / and drop tabs and newlines, so "/\\evil.com" or "/\t/evil.com" would leave the site.
    if "\\" in value or any(ord(ch) < 0x20 or ord(ch) == 0x7F for ch in value):
        return "/"
    return value


def _enabled():
    return current_app.config["AUTH_ENABLED"]


def _redirect_uri():
    return current_app.config["PUBLIC_URL"] + "/auth/callback"


def _back(next_path, outcome=None):
    if outcome:
        next_path += ("&" if "?" in next_path else "?") + f"signin={outcome}"
    return redirect(next_path, code=303)


def no_store(response):
    response.headers["Cache-Control"] = "no-store"
    return response


def _exchange_code(code):
    """Trade an authorization code for Google's token response, or None (logged, without the tokens)."""
    try:
        resp = requests.post(GOOGLE_TOKEN_URL, timeout=15, data={
            "code": code,
            "client_id": current_app.config["GOOGLE_CLIENT_ID"],
            "client_secret": os.environ.get("GOOGLE_CLIENT_SECRET", ""),
            "redirect_uri": _redirect_uri(),
            "grant_type": "authorization_code",
        })
        body = resp.json() if resp.status_code == 200 else None
    except (requests.RequestException, ValueError) as exc:
        log.warning("Google token exchange failed: %s", type(exc).__name__)
        return None
    if not isinstance(body, dict):
        log.warning("Google token exchange returned HTTP %s", resp.status_code)
        return None
    return body


@bp.get("/login")
def login():
    if not _enabled():
        abort(404)
    state = secrets.token_urlsafe(32)
    session.clear()
    session["oauth_state"] = state
    session["oauth_next"] = safe_next(request.args.get("next"))
    params = {
        "client_id": current_app.config["GOOGLE_CLIENT_ID"],
        "redirect_uri": _redirect_uri(),
        "response_type": "code",
        "scope": SCOPES,
        "state": state,
        "prompt": "select_account",
    }
    return no_store(redirect(f"{GOOGLE_AUTH_URL}?{urlencode(params)}", code=303))


@bp.get("/callback")
def callback():
    if not _enabled():
        abort(404)
    expected = session.pop("oauth_state", None)
    next_path = safe_next(session.pop("oauth_next", None))
    session.clear()
    state = request.args.get("state")
    if not (state and isinstance(expected, str) and secrets.compare_digest(state.encode(), expected.encode())):
        # A forged callback, or a stale one (a second login tab, Back into the callback): nobody is signed in.
        log.warning("sign-in callback with a missing or wrong state")
        return no_store(_back(next_path, "error"))
    code = request.args.get("code")
    if request.args.get("error") or not code:
        return no_store(_back(next_path, "error"))
    body = _exchange_code(code)
    token = body.get("id_token") if body else None
    if not isinstance(token, str) or not token:
        if body is not None:
            log.warning("Google token exchange returned no id_token")
        return no_store(_back(next_path, "error"))
    try:
        info = id_token.verify_oauth2_token(token, google_requests.Request(), current_app.config["GOOGLE_CLIENT_ID"],
                                            clock_skew_in_seconds=CLOCK_SKEW_SECONDS)
    except (ValueError, GoogleAuthError) as exc:
        log.warning("Google ID token rejected: %s", type(exc).__name__)
        return no_store(_back(next_path, "error"))
    if not info.get("email_verified") or not info.get("email") or not info.get("sub"):
        return no_store(_back(next_path, "error"))
    session.permanent = True
    session["sub"] = str(info["sub"])
    session["email"] = str(info["email"])
    session["name"] = str(info.get("name") or "")
    return no_store(_back(next_path))


def _signed_in():
    return bool(session.get("sub") and session.get("email"))


def current_email():
    """The signed-in visitor's email, or None."""
    return session["email"] if _enabled() and _signed_in() else None


def current_access():
    """What the current visitor may open. A database error is logged and answered in env-only mode."""
    email = current_email()
    try:
        with perms.db() as conn:
            return perms.access_for(conn, email)
    except Exception as exc:
        log.warning("site permissions database unavailable, using env-only mode: %s", type(exc).__name__)
        return perms.access_for(None, email)


@bp.get("/me")
def me():
    signed_in = current_email() is not None
    access = current_access()
    return no_store(jsonify(
        enabled=_enabled(),
        signed_in=signed_in,
        email=session.get("email") if signed_in else None,
        name=(session.get("name") or None) if signed_in else None,
        admin=access.admin,
        pages=[key for key in perms.PAGE_KEYS if key in access.pages],
    ))


@bp.post("/logout")
def logout():
    # SameSite=Lax already keeps cross-site POSTs from carrying the cookie.
    session.clear()
    return no_store(current_app.response_class(status=204))


@bp.get("/verify")
def verify():
    """For nginx auth_request, with the identity headers (oauth2-proxy's names) only when signed in.

    Without ?page= it always answers 204. With ?page=<key>: 204 plus X-Auth-Request-Access/-Admin (and -Cap-Usd for
    cap pages) when the visitor may open that page, else 401 signed out or 403 signed in. Unknown key: 404.
    """
    key = request.args.get("page")
    response = current_app.response_class(status=204)
    if key is not None:
        try:
            page = perms.page(key)
        except perms.PermsError:
            abort(404)
        access = current_access()
        if key not in access.pages:
            return no_store(current_app.response_class(status=403 if access.email else 401))
        response.headers["X-Auth-Request-Access"] = key
        response.headers["X-Auth-Request-Admin"] = "1" if access.admin else "0"
        if page.cap:
            response.headers["X-Auth-Request-Cap-Usd"] = "none" if access.cap_usd is None else f"{access.cap_usd:.2f}"
    if current_email():
        response.headers["X-Auth-Request-Email"] = session["email"]
        response.headers["X-Auth-Request-User"] = session["sub"]
        # Headers are Latin-1, so the display name is percent-encoded (the dashboard unquotes it).
        response.headers["X-Auth-Request-Preferred-Username"] = quote(session.get("name") or "", safe="")
    return no_store(response)
