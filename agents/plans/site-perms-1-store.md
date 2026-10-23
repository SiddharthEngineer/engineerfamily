# Plan: Site permissions 1/4: permissions store, admin API, per-page verify
**Status:** 🔄 In progress
**Risk:** review (new Postgres DB, compose, Makefile and scripts, and the auth endpoint nginx trusts)

## Goal
engineerfamily becomes the one place that decides who may use which part of the site. This part adds the data and the API
only (no UI, no nginx change yet, so nothing visible changes): a users table in a new `engineerfamily` Postgres database,
per-page grants, an admin flag and a Strelitzia monthly spend cap per user, plus an "everyone" row for visitors who are signed
out or not invited. `/auth/verify?page=<key>` answers whether the current visitor may open that page, so part 3 can wire nginx.

## Context
- `services/app/auth.py:1-196`: the session (`sub`, `email`, `name`), `/auth/me`, `/auth/verify` (204 + `X-Auth-Request-*`).
  Keep its style: `_no_store`, `log` without secrets, Blueprint.
- `services/app/test_auth.py`: test style to mirror (Flask test client, monkeypatched env).
- `scripts/init-strelitzia-db.sh:1-60` and `Makefile:139-140,185-186`: copy for `scripts/init-site-db.sh` and the targets.
- `docker-compose.prod.yml:25-45,80-131`, `docker-compose.preprod.yml:29-45,79-115`: the `app` service and `postgres-db`.
  `postgres-db` is on `dashboard`, which must stay nginx + strelitzia + postgres-db only (strelitzia trusts headers). Give
  `app` and `postgres-db` a new shared network (`sitedb`) instead of putting `app` on `dashboard`.
- Strelitzia's model to borrow from (read only): `../Strelitzia/src/strelitzia/users.py` (lowercased emails, idempotent
  invite with `ON CONFLICT DO NOTHING`) and `web/admin.py` (guards: you can't disable yourself).
- Gotcha: tests must stay hermetic (no Postgres in CI). Write the store against a DB-API connection and run the tests on
  `sqlite3` in memory; use only SQL both accept (`?` placeholders translated to `%s` for psycopg).
- Gotcha: the user's and the test account's emails must never be committed (public repo). They come from `.env` only.

## Tasks
### Task 1: Permissions store
**Runs:** unattended
**Files:** services/app/perms.py (new), services/app/test_perms.py (new), services/app/requirements.txt (modify: `psycopg[binary]>=3.1`)
**What:**
- `PAGES: tuple[Page, ...]` with `@dataclass(frozen=True) class Page: key: str; label: str; cap: bool = False;
  needs_account: bool = False`. Entries, in column order: `site` "Site" (the whole site), `strelitzia` "Strelitzia"
  (`cap=True, needs_account=True`), `bracket` "Bracket Analyzer" (no page yet; the column exists so future pages slot in).
  Adding a page later = one entry here + one nginx location.
- Tables (created if missing at startup): `site_users(email TEXT PRIMARY KEY, admin BOOLEAN NOT NULL DEFAULT FALSE,
  cap_usd NUMERIC NULL, created_at TEXT NOT NULL)` and `site_grants(email TEXT, page TEXT, PRIMARY KEY (email, page))`.
  The everyone row is `email = '*'` in `site_users` (admin always false, cap unused).
- `@dataclass class Access: email: str | None; admin: bool; pages: frozenset[str]; cap_usd: float | None`.
- `access_for(conn, email: str | None) -> Access`: admin → every page, `cap_usd=None` (no cap). A listed user → their grants and
  cap. Anyone else (signed out, or signed in but not listed) → the everyone row's grants minus `needs_account` pages.
- `list_rows(conn)`, `invite(conn, email) -> row` (idempotent; a new user starts with the everyone row's grants and
  `cap_usd = DEFAULT_CAP_USD = 5.0`), `set_admin`, `set_grant(conn, email, page, allowed)`, `set_cap(conn, email, cap | None)`,
  `remove(conn, email)`. Guards raise `PermsError`: unknown page; changing the last admin's admin flag or removing them;
  `needs_account` grants or a cap on `'*'`.
- `seed(conn, admins, members, everyone)` runs at startup and does nothing unless `site_users` is empty: admins → admin rows;
  members → rows with every page granted and cap 5.0; `'*'` row with the pages listed in `everyone`.
- `connect()`: psycopg from `SITE_DATABASE_URL`. Unset → `None`, and the app runs in **env-only mode**: `access_for` uses
  `SITE_ADMIN_EMAILS` as admins and `SITE_EVERYONE` for everyone else, and every write raises `PermsError("no database")`.
- Anti-lockout: if no admin exists at all (empty DB, no `SITE_ADMIN_EMAILS`), everyone gets `site`, so a deploy before
  the user's `.env` step leaves the site as open as today.
**Validate:** `cd services/app && python -m pytest test_perms.py -q` → passes; it covers admin = everything, the everyone
fallback, `needs_account` stripped for strangers, the last-admin guard, seed only on an empty DB, env-only mode, anti-lockout.
**Status:** ✅ 2026-10-23 (`feat(site-perms-1-store): Task 1`)

### Task 2: Admin API and per-page verify
**Runs:** unattended
**Files:** services/app/admin.py (new), services/app/auth.py (modify), services/app/app.py (modify: register, seed at startup), services/app/test_perms.py (modify)
**What:**
- `/auth/verify?page=<key>` (default `site`, unknown key → 404): allowed → 204 with today's identity headers plus
  `X-Auth-Request-Access: <key>`, `X-Auth-Request-Admin: 1|0`, and for cap pages `X-Auth-Request-Cap-Usd: <number>|none`.
  Not allowed → 401 when signed out, 403 when signed in. DB error → logged, then behave as env-only mode (fail closed for
  everything except what `SITE_EVERYONE` grants). Plain `/auth/verify` with no `page` keeps today's always-204 behaviour
  until part 3 switches nginx over, so this part changes nothing live.
- `/auth/me` adds `admin: bool` and `pages: [keys the visitor may open]` (the header menu uses both in part 2).
- Blueprint `admin` at `/api/admin`, admin-only (403 otherwise, 401 signed out): `GET /users` →
  `{pages: [{key,label,cap,needs_account}], everyone: {...}, users: [{email, admin, pages: [...], cap_usd}], db: bool}`;
  `POST /users {email}` (validate like Strelitzia's `looks_like_email`; 409 if present); `PATCH /users/<email>
  {admin?, pages?: {key: bool}, cap_usd?: number|null}`; `PATCH /everyone {pages: {key: bool}}`; `DELETE /users/<email>`.
  `PermsError` → 400 with its message. Writes require `Content-Type: application/json` (CSRF: SameSite=Lax plus no simple
  form posts). Every response `no-store`.
- Startup (`app.py`): `perms.connect()`, create tables, `seed(...)` from `SITE_ADMIN_EMAILS`, `SITE_MEMBER_EMAILS`
  (comma lists) and `SITE_EVERYONE` (comma list of page keys, may be empty). Log counts, never emails.
**Validate:** `cd services/app && python -m pytest -q` → all pass, including: non-admin gets 403 on `/api/admin/users`;
verify returns the Access/Admin/Cap headers; `?page=strelitzia` 403 for a signed-in stranger; no-`page` verify unchanged.
**Status:** ✅ 2026-10-23 (`feat(site-perms-1-store): Task 2`)

### Task 3: Database wiring (compose, init script, make targets)
**Runs:** unattended (writing the files); creating the DBs and the `.env` values is the user's ROADMAP step M2
**Files:** scripts/init-site-db.sh (new), Makefile (modify), docker-compose.prod.yml (modify), docker-compose.preprod.yml (modify), .env.template (modify)
**What:** `init-site-db.sh [prod|preprod]` creates role `engineerfamily` and DB `engineerfamily` (prod, `SITE_DB_PASSWORD`)
or `engineerfamily_preprod` (preprod, `SITE_DB_PASSWORD_PREPROD`), idempotent, same checks as the Strelitzia script.
Targets `site-db-init` and `preprod-site-db-init` (+ help lines). Compose `app`: `SITE_DATABASE_URL` built from the password
only when it is set (`${SITE_DB_PASSWORD:+postgresql://engineerfamily:${SITE_DB_PASSWORD}@postgres-db:5432/engineerfamily}`),
`SITE_ADMIN_EMAILS=${SITE_ADMIN_EMAILS:-}`, `SITE_MEMBER_EMAILS=${SITE_MEMBER_EMAILS:-}`, and `SITE_EVERYONE` written in the
compose file: prod `site`, preprod empty. New `sitedb` network on `app` and `postgres-db`; `app` keeps `web`.
`.env.template`: the new variables, commented, with no real emails.
**Validate:** `scripts/validate.sh` → passes (bash -n, compose config for all envs, nginx -t).
**Status:** ✅ 2026-10-23 (`feat(site-perms-1-store): Task 3`; creating the DBs and the `.env` values is still M2)

## Validation
- `scripts/validate.sh` passes; `cd services/app && python -m pytest -q` passes.
- On preprod after deploy: `curl -s -o /dev/null -w "%{http_code}" https://preprod.engineerfamily.net/` → 200 (nothing gated yet);
  `curl -s https://preprod.engineerfamily.net/auth/me` has an `admin` field; `curl -s -o /dev/null -w "%{http_code}"
  https://preprod.engineerfamily.net/api/admin/users` → 401.

## Human test steps (preprod)
1. Do ROADMAP M2 (preprod half): add the `.env` lines, run `make preprod-site-db-init`, then `make preprod-deploy`.
2. Signed in as yourself, open `https://preprod.engineerfamily.net/api/admin/users`: JSON with `db: true`, you and the test
   account as admins, and an `everyone` row with no pages.

## Decisions
1. Postgres (`engineerfamily` DB in the existing postgres-db), as the user chose; env-only mode keeps deploys safe before M2.
2. Seed emails live in the `/srv` `.env` files (user's choice), so they never land in the public repo.
3. Seeding runs only on an empty table: after that the Users page is the source of truth.
4. A new grant of Strelitzia starts at a $5/month cap (Strelitzia's current default); blank means no cap; admins have none.
5. Signed-in people who aren't on the list get the everyone row, minus pages that need an account (Strelitzia).
6. "Base" is named "Site".
