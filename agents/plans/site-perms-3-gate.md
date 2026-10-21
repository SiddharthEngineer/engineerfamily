# Plan: Site permissions 3/4: nginx enforces Site and per-page access
**Status:** ❌ Not started
**Risk:** review (nginx on every public route; a mistake locks people out or opens a page)
**Depends on:** site-perms-1-store, site-perms-2-users-page

## Goal
The permissions from part 1 take effect. Every page on `engineerfamily.net` / `preprod.engineerfamily.net` needs the
**Site** grant; `/strelitzia/dashboard/` also needs **Strelitzia**; `/bracket/` (future) needs **Bracket Analyzer**.
Someone without access sees a small page: signed out → "Sign in to continue" with a Sign in button; signed in → "You don't
have access to this page. Ask an admin." On prod the Everyone row has Site, so the public site is unchanged; on preprod the
Everyone row has nothing, so preprod is sign-in-only. Strelitzia receives the visitor's admin flag and cap.

## Context
- `services/nginx/nginx.prod.conf:5-98` (and `nginx.preprod.conf:7-110`, which repeats `X-Robots-Tag` in every location
  with its own `add_header`): `location /`, `/shared/`, `/strelitzia/`, `/_auth_verify`, `/strelitzia/dashboard/` (+ assets).
- `services/nginx/nginx.local.conf:5-40`: local has no auth; leave it ungated unless it already proxies `/auth/`.
- `services/app/auth.py`: `/auth/verify?page=` from part 1 (204 / 401 / 403, plus `X-Auth-Request-Access`, `-Admin`,
  `-Cap-Usd`). Plain `/auth/verify` (no page) still always answers 204; switch every nginx caller to a `?page=` URL.
- Gotcha: `auth_request` only accepts 2xx, 401, 403 from the subrequest; anything else is a 500. Part 1 maps DB errors to
  401/403 already; keep it that way.
- Gotcha: nginx `auth_request` can't take a query string from a variable cleanly; use one internal location per page
  (`/_auth_site`, `/_auth_strelitzia`, `/_auth_bracket`) each proxying to `http://app:8000/auth/verify?page=<key>`.
- Gotcha: a location with its own `auth_request` replaces a server-level one, so set the Site check at server level and
  override per page; `auth_request off` where a path must stay open.
- Must stay open (no Site check): `/auth/` (login, callback, me, logout, the no-access pages), `/privacy` and
  `/strelitzia/privacy` (Google's consent screen links them), `/healthz`, `/robots.txt`, `/shared/` and `/favicon.ico`
  (the no-access page uses the site header), the Vite `/assets/` (static bundle, no data), and the internal
  `127.0.0.1` health server. The static `/strelitzia/` about page is under Site, not Strelitzia.

## Tasks
### Task 1: No-access pages
**Runs:** unattended
**Files:** services/app/auth.py (modify), services/app/test_auth.py (modify)
**What:** `GET /auth/denied?status=401|403&next=<path>` returns a small standalone HTML page (no-store, status 401 or 403
to match) with the shared header (`/shared/site-header.js`, `<ef-home>`, `<ef-profile next=...>`), and either a Sign in
link to `/auth/login?next=<safe_next(next)>` (401) or "You don't have access to this page. Ask an admin." (403). Escape
`next`. Reuse `safe_next`.
**Validate:** `cd services/app && python -m pytest -q` → passes, including the escaping and open-redirect cases.
**Status:** ❌

### Task 2: Gate prod and preprod in nginx
**Runs:** unattended
**Files:** services/nginx/nginx.prod.conf (modify), services/nginx/nginx.preprod.conf (modify)
**What:**
- Internal locations `/_auth_site`, `/_auth_strelitzia`, `/_auth_bracket` (same headers as today's `/_auth_verify`,
  which they replace). Keep `location = /auth/verify { return 404; }`.
- Server level on the main vhost: `auth_request /_auth_site;` plus `error_page 401 = @denied401; error_page 403 =
  @denied403;` where the named locations proxy to `/auth/denied?status=…&next=$request_uri` (escape-safe: pass
  `$request_uri` as a header `X-Original-URI` and have Flask read it if a query arg is awkward).
- `auth_request off;` on each open path listed in Context.
- `/strelitzia/dashboard/`: `auth_request /_auth_strelitzia;`, `auth_request_set` and `proxy_set_header` for the three
  existing headers plus `X-Auth-Request-Access`, `X-Auth-Request-Admin`, `X-Auth-Request-Cap-Usd`; the assets block clears
  all six. Update the comment ("every location that proxies to strelitzia must set all six").
- `location /bracket/ { auth_request /_auth_bracket; return 404; }` as the placeholder for the future page.
- Other vhosts that serve site content (www, `strelitzia(-preprod)`/`applypilot(-preprod)` redirects) only redirect to
  the main host today; confirm that and leave them. Don't touch umami/streamlit vhosts.
**Validate:** `scripts/validate.sh` → passes (`nginx -t` for each conf).
**Status:** ❌

### Task 3: Docs
**Runs:** unattended
**Files:** README.md (modify), agents/DEPLOY.md (modify)
**What:** README routing section: what Site / per-page grants gate, which paths stay open, how to add a restricted page
(one `PAGES` entry in `services/app/perms.py` + one `/_auth_<key>` location). DEPLOY.md: the M2 steps (DB init, `.env`
variables, no real emails) and that prod needs them before the first prod deploy containing parts 1-3.
**Validate:** `scripts/validate.sh` → passes.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes; `cd services/app && python -m pytest -q` passes.
- Preprod, after M2 and deploy (signed out, through Cloudflare):
  `curl -s -o /dev/null -w "%{http_code}" https://preprod.engineerfamily.net/` → 401;
  `…/privacy` → 200; `…/strelitzia/privacy` → 200; `…/healthz` → 200; `…/shared/site-header.js` → 200;
  `…/strelitzia/dashboard/` → 401; `curl -s https://preprod.engineerfamily.net/ | grep -c "Sign in"` → ≥1.
- If M2 isn't done yet (no admins), the anti-lockout rule keeps preprod at Site for everyone: `/` → 200. Note that in the PR.

## Human test steps (preprod)
1. In a private window open `https://preprod.engineerfamily.net/`: "Sign in to continue". `/privacy` still opens.
2. Sign in as yourself: the home page loads; the Strelitzia dashboard opens.
3. On the Users page tick Site for Everyone; the private window can now see the home page but `/strelitzia/dashboard/`
   still asks to sign in. Untick it again.
4. Invite a second Google account you own with Site only, sign in with it: the dashboard says you don't have access.

## Decisions
1. nginx enforces access (one `auth_request` per page key) so every service behind it is covered, not just Flask.
2. Privacy pages, health checks and static assets stay open; Google and uptime checks need them.
3. Prod looks unchanged to the public because its Everyone row starts with Site.
