"""Admin-only JSON API for site permissions at /api/admin/* (the Users page uses it).

401 signed out, 403 for non-admins. Writes need Content-Type: application/json: with SameSite=Lax that keeps
cross-site form posts out (CSRF). A refused change (perms.PermsError) is 400 with its message. Every response is no-store.
"""

import logging

from flask import Blueprint, current_app, jsonify, request

import auth
import perms


log = logging.getLogger(__name__)

bp = Blueprint("admin", __name__, url_prefix="/api/admin")


def init_app(app):
    app.register_blueprint(bp)


def _error(status, message):
    response = jsonify(error=message)
    response.status_code = status
    return response


@bp.before_request
def _admins_only():
    if auth.current_email() is None:
        return _error(401, "sign in first")
    if not auth.current_access().admin:
        return _error(403, "admins only")
    if request.method not in ("GET", "HEAD") and not request.is_json:
        return _error(415, "send JSON (Content-Type: application/json)")
    return None


@bp.after_request
def _after(response):
    return auth.no_store(response)


@bp.errorhandler(perms.PermsError)
def _refused(exc):
    return _error(404 if isinstance(exc, perms.NotFound) else 400, str(exc))


def _body():
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        raise perms.PermsError("the body must be a JSON object")
    return body


def _page_changes(value):
    """{key: bool} from the body, checked before anything is written."""
    if not isinstance(value, dict) or not all(isinstance(v, bool) for v in value.values()):
        raise perms.PermsError("pages must be an object of page key to true or false")
    for key in value:
        perms.page(key)
    return value


def _with_db(work):
    """Run work(conn) in one transaction; a refused change is 400/404, a database that is down is 503."""
    try:
        with perms.db() as conn:
            return work(conn)
    except perms.PermsError:
        raise
    except Exception as exc:
        log.warning("site permissions database error: %s", type(exc).__name__)
        return _error(503, "the permissions database is unavailable")


def _not_everyone(email):
    if perms.norm_email(email) == perms.EVERYONE:
        raise perms.PermsError("change everyone at /api/admin/everyone")
    return perms.norm_email(email)


def _not_me(email, what):
    if email == perms.norm_email(auth.current_email()):
        raise perms.PermsError(f"you can't {what} yourself")


@bp.get("/users")
def users():
    return _with_db(lambda conn: jsonify(
        pages=[{"key": p.key, "label": p.label, "cap": p.cap, "needs_account": p.needs_account} for p in perms.PAGES],
        everyone=perms.everyone(conn).to_dict(),
        users=[row.to_dict() for row in perms.list_rows(conn)],
        db=conn is not None,
    ))


@bp.post("/users")
def add_user():
    email = _body().get("email")
    if not isinstance(email, str) or not perms.looks_like_email(email):
        raise perms.PermsError("that doesn't look like an email address")

    def work(conn):
        if conn is not None and perms.get_row(conn, email):
            return _error(409, "already on the list")
        response = jsonify(perms.invite(conn, email).to_dict())
        response.status_code = 201
        return response
    return _with_db(work)


@bp.patch("/users/<email>")
def change_user(email):
    email = _not_everyone(email)
    body = _body()
    admin = body.get("admin")
    if "admin" in body and not isinstance(admin, bool):
        raise perms.PermsError("admin must be true or false")
    if admin is False:
        _not_me(email, "remove the admin flag from")
    pages = _page_changes(body["pages"]) if "pages" in body else {}
    cap = perms.check_cap(body["cap_usd"]) if "cap_usd" in body else None

    def work(conn):
        row = perms.get_row(conn, email)
        if row is None:
            raise perms.NotFound("no such user")
        if "admin" in body:
            row = perms.set_admin(conn, email, admin)
        for key, allowed in pages.items():
            row = perms.set_grant(conn, email, key, allowed)
        if "cap_usd" in body:
            row = perms.set_cap(conn, email, cap)
        return jsonify(row.to_dict())
    return _with_db(work)


@bp.patch("/everyone")
def change_everyone():
    pages = _page_changes(_body().get("pages"))

    def work(conn):
        perms.need_db(conn)
        for key, allowed in pages.items():
            perms.set_grant(conn, perms.EVERYONE, key, allowed)
        return jsonify(perms.everyone(conn).to_dict())
    return _with_db(work)


@bp.delete("/users/<email>")
def delete_user(email):
    email = _not_everyone(email)
    _not_me(email, "remove")

    def work(conn):
        perms.remove(conn, email)
        return current_app.response_class(status=204)
    return _with_db(work)
