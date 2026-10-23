"""Who may open which part of the site: users, per-page grants, an admin flag and a Strelitzia spend cap.

Kept in the `engineerfamily` Postgres DB (SITE_DATABASE_URL). The row with email '*' is "everyone": visitors who are
signed out or not on the list. Without SITE_DATABASE_URL the app runs in env-only mode: SITE_ADMIN_EMAILS are admins,
everyone else gets SITE_EVERYONE, and every write raises PermsError("no database"). While no admin exists at all,
everyone gets `site`, so a deploy before the .env step leaves the site as open as it was.

The SQL is the subset sqlite3 and Postgres both accept (`?` placeholders become `%s` for psycopg), so the tests run on
an in-memory sqlite3 DB. The write functions don't commit: `db()` commits once the request's block finishes.
"""

import logging
import math
import os
import sqlite3
from contextlib import contextmanager
from dataclasses import asdict, dataclass
from datetime import datetime, timezone

from flask import current_app


log = logging.getLogger(__name__)

EVERYONE = "*"
DEFAULT_CAP_USD = 5.0


@dataclass(frozen=True)
class Page:
    key: str
    label: str
    cap: bool = False
    needs_account: bool = False


# Adding a page = one entry here + one nginx location.
PAGES: tuple[Page, ...] = (
    Page("site", "Site"),
    Page("strelitzia", "Strelitzia", cap=True, needs_account=True),
    Page("bracket", "Bracket Analyzer"),
)
PAGE_KEYS = tuple(p.key for p in PAGES)
_BY_KEY = {p.key: p for p in PAGES}


class PermsError(Exception):
    """A change the store refuses; the message is safe to show to an admin."""


class NotFound(PermsError):
    pass


@dataclass
class Access:
    email: str | None
    admin: bool
    pages: frozenset[str]
    cap_usd: float | None


@dataclass
class Row:
    email: str
    admin: bool
    pages: list[str]
    cap_usd: float | None

    def to_dict(self):
        return asdict(self)


def page(key) -> Page:
    if key not in _BY_KEY:
        raise PermsError(f"unknown page: {key}")
    return _BY_KEY[key]


def check_cap(cap):
    """None (no cap) or a finite number >= 0, as a float."""
    if cap is None:
        return None
    if isinstance(cap, bool) or not isinstance(cap, (int, float)) or not math.isfinite(cap) or cap < 0:
        raise PermsError("the cap must be a number of dollars, 0 or more, or empty for no cap")
    return float(cap)


def norm_email(email):
    return (email or "").strip().lower()


def looks_like_email(email) -> bool:
    """A local part, a dotted domain and no whitespace: enough to catch typos before an invite nobody can use."""
    email = norm_email(email)
    local, _, domain = email.partition("@")
    return bool(local) and "." in domain and not any(c.isspace() for c in email)


def _ordered(keys):
    return [k for k in PAGE_KEYS if k in keys]


def _emails(value):
    return [e for e in (norm_email(part) for part in (value or "").split(",")) if e]


def _page_keys(value):
    keys = [k.strip() for k in (value or "").split(",") if k.strip()]
    unknown = [k for k in keys if k not in _BY_KEY]
    if unknown:
        log.warning("ignoring %d unknown page key(s) in SITE_EVERYONE", len(unknown))
    return [k for k in keys if k in _BY_KEY]


def _strip_account_pages(keys):
    return frozenset(k for k in keys if not _BY_KEY[k].needs_account)


# --- SQL helpers ---

def _run(conn, sql, params=()):
    if not isinstance(conn, sqlite3.Connection):
        sql = sql.replace("?", "%s")
    cur = conn.cursor()
    cur.execute(sql, params)
    return cur


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def need_db(conn):
    if conn is None:
        raise PermsError("no database")


def create_tables(conn):
    _run(conn, "CREATE TABLE IF NOT EXISTS site_users (email TEXT PRIMARY KEY, admin BOOLEAN NOT NULL DEFAULT FALSE,"
               " cap_usd NUMERIC NULL, created_at TEXT NOT NULL)")
    _run(conn, "CREATE TABLE IF NOT EXISTS site_grants (email TEXT NOT NULL, page TEXT NOT NULL,"
               " PRIMARY KEY (email, page))")


def _get(conn, email) -> Row | None:
    found = _run(conn, "SELECT email, admin, cap_usd FROM site_users WHERE email = ?", (email,)).fetchone()
    if not found:
        return None
    grants = {r[0] for r in _run(conn, "SELECT page FROM site_grants WHERE email = ?", (email,)).fetchall()}
    cap = found[2]
    return Row(found[0], bool(found[1]), _ordered(grants), None if cap is None else float(cap))


def _must_get(conn, email) -> Row:
    row = _get(conn, email)
    if row is None:
        raise NotFound("no such user")
    return row


def _admin_count(conn):
    return _run(conn, "SELECT COUNT(*) FROM site_users WHERE admin = ?", (True,)).fetchone()[0]


def _insert_user(conn, email, admin, cap, pages):
    _run(conn, "INSERT INTO site_users (email, admin, cap_usd, created_at) VALUES (?, ?, ?, ?)"
               " ON CONFLICT DO NOTHING", (email, admin, cap, _now()))
    for key in pages:
        _run(conn, "INSERT INTO site_grants (email, page) VALUES (?, ?) ON CONFLICT DO NOTHING", (email, key))


# --- reads ---

def _env_access(email) -> Access:
    admins = _emails(os.environ.get("SITE_ADMIN_EMAILS"))
    if email and email in admins:
        return Access(email, True, frozenset(PAGE_KEYS), None)
    pages = _strip_account_pages(_page_keys(os.environ.get("SITE_EVERYONE")))
    if not admins:
        pages |= {"site"}
    return Access(email, False, pages, None)


def access_for(conn, email: str | None) -> Access:
    """What this visitor may open. `conn` None (no database) means env-only mode."""
    email = norm_email(email) or None
    if email == EVERYONE:
        email = None
    if conn is None or not _admin_count(conn):
        # No database, or nobody seeded yet: the env decides, and anti-lockout keeps `site` open without admins.
        return _env_access(email)
    row = _get(conn, email) if email else None
    if row and row.admin:
        return Access(email, True, frozenset(PAGE_KEYS), None)
    if row:
        return Access(email, False, frozenset(row.pages), row.cap_usd)
    everyone = _get(conn, EVERYONE)
    return Access(email, False, _strip_account_pages(everyone.pages if everyone else ()), None)


def list_rows(conn) -> list[Row]:
    """Every listed user (not the everyone row), oldest first. Env-only mode lists the env admins."""
    if conn is None:
        return [Row(e, True, list(PAGE_KEYS), None) for e in _emails(os.environ.get("SITE_ADMIN_EMAILS"))]
    emails = [r[0] for r in _run(conn, "SELECT email FROM site_users WHERE email <> ? ORDER BY created_at, email",
                                 (EVERYONE,)).fetchall()]
    return [_get(conn, e) for e in emails]


def everyone(conn) -> Row:
    """The everyone row as `access_for` applies it to a stranger."""
    pages = sorted(access_for(conn, None).pages, key=PAGE_KEYS.index)
    return Row(EVERYONE, False, pages, None)


def get_row(conn, email) -> Row | None:
    need_db(conn)
    return _get(conn, norm_email(email))


# --- writes (the caller commits) ---

def invite(conn, email) -> Row:
    """Add a user (idempotent). They start with the everyone row's grants and a DEFAULT_CAP_USD cap."""
    need_db(conn)
    email = norm_email(email)
    if email == EVERYONE or not looks_like_email(email):
        raise PermsError("that doesn't look like an email address")
    existing = _get(conn, email)
    if existing:
        return existing
    start = _get(conn, EVERYONE)
    _insert_user(conn, email, False, DEFAULT_CAP_USD, start.pages if start else ())
    return _get(conn, email)


def set_admin(conn, email, admin: bool) -> Row:
    need_db(conn)
    email = norm_email(email)
    if email == EVERYONE:
        raise PermsError("everyone can't be an admin")
    row = _must_get(conn, email)
    if row.admin and not admin and _admin_count(conn) <= 1:
        raise PermsError("can't remove the last admin")
    _run(conn, "UPDATE site_users SET admin = ? WHERE email = ?", (bool(admin), email))
    return _get(conn, email)


def set_grant(conn, email, key, allowed: bool) -> Row:
    """Grant or revoke one page. A new grant of a cap page starts at DEFAULT_CAP_USD."""
    need_db(conn)
    email = norm_email(email)
    p = page(key)
    row = _must_get(conn, email)
    if email == EVERYONE and p.needs_account and allowed:
        raise PermsError(f"{p.label} needs an account, so everyone can't have it")
    if allowed and key not in row.pages:
        _run(conn, "INSERT INTO site_grants (email, page) VALUES (?, ?) ON CONFLICT DO NOTHING", (email, key))
        if p.cap and email != EVERYONE:
            _run(conn, "UPDATE site_users SET cap_usd = ? WHERE email = ?", (DEFAULT_CAP_USD, email))
    elif not allowed:
        _run(conn, "DELETE FROM site_grants WHERE email = ? AND page = ?", (email, key))
    return _get(conn, email)


def set_cap(conn, email, cap) -> Row:
    """Monthly Strelitzia spend cap in dollars; None means no cap."""
    need_db(conn)
    email = norm_email(email)
    if email == EVERYONE:
        raise PermsError("everyone has no cap")
    cap = check_cap(cap)
    _must_get(conn, email)
    _run(conn, "UPDATE site_users SET cap_usd = ? WHERE email = ?", (cap, email))
    return _get(conn, email)


def remove(conn, email):
    need_db(conn)
    email = norm_email(email)
    if email == EVERYONE:
        raise PermsError("the everyone row can't be removed")
    row = _must_get(conn, email)
    if row.admin and _admin_count(conn) <= 1:
        raise PermsError("can't remove the last admin")
    _run(conn, "DELETE FROM site_grants WHERE email = ?", (email,))
    _run(conn, "DELETE FROM site_users WHERE email = ?", (email,))


def seed(conn, admins, members, everyone_pages) -> dict | None:
    """Fill an empty site_users once; after that the Users page is the source of truth.

    Does nothing without admins, so the env keeps deciding (and seeding can still happen) until SITE_ADMIN_EMAILS is set.
    Returns the counts it wrote, or None.
    """
    if _run(conn, "SELECT COUNT(*) FROM site_users").fetchone()[0]:
        return None
    admins = [norm_email(e) for e in admins if norm_email(e) and norm_email(e) != EVERYONE]
    if not admins:
        return None
    members = [m for m in (norm_email(e) for e in members) if m and m != EVERYONE and m not in admins]
    for email in dict.fromkeys(admins):
        _insert_user(conn, email, True, None, PAGE_KEYS)
    for email in dict.fromkeys(members):
        _insert_user(conn, email, False, DEFAULT_CAP_USD, PAGE_KEYS)
    pages = sorted(_strip_account_pages(k for k in everyone_pages if k in _BY_KEY), key=PAGE_KEYS.index)
    _insert_user(conn, EVERYONE, False, None, pages)
    return {"admins": len(set(admins)), "members": len(set(members)), "everyone_pages": len(pages)}


# --- connection and Flask glue ---

def connect():
    """A psycopg connection from SITE_DATABASE_URL, or None (env-only mode) when it is unset."""
    url = os.environ.get("SITE_DATABASE_URL", "").strip()
    if not url:
        return None
    import psycopg  # only the container needs the driver; the tests run on sqlite3

    return psycopg.connect(url, connect_timeout=3)


def prepare(conn):
    """Create the tables and seed them from the env. Logs counts, never emails."""
    create_tables(conn)
    counts = seed(conn, _emails(os.environ.get("SITE_ADMIN_EMAILS")), _emails(os.environ.get("SITE_MEMBER_EMAILS")),
                  _page_keys(os.environ.get("SITE_EVERYONE")))
    conn.commit()
    if counts:
        log.info("seeded site permissions: %(admins)d admin(s), %(members)d member(s), "
                 "%(everyone_pages)d page(s) for everyone", counts)


@contextmanager
def db():
    """The request's connection (None in env-only mode). Commits when the block ends, rolls back on an exception.

    The first connection in each process creates and seeds the tables, so a database that came up after the app
    still gets them.
    """
    app = current_app
    conn = app.config.get("PERMS_CONNECT", connect)()
    if conn is None:
        yield None
        return
    try:
        if not app.extensions.get("perms_ready"):
            prepare(conn)
            app.extensions["perms_ready"] = True
        yield conn
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_app(app):
    """Use SITE_DATABASE_URL and try the tables and seed now; a DB that is down is retried on the next request."""
    app.config.setdefault("PERMS_CONNECT", connect)
    app.extensions["perms_ready"] = False
    with app.app_context():
        try:
            with db() as conn:
                log.info("site permissions: %s", "database" if conn is not None else "env-only mode (no database)")
        except Exception as exc:
            log.warning("site permissions database unavailable at startup: %s", type(exc).__name__)
