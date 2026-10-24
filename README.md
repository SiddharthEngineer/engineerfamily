# Engineer Family Website

Personal family website running on a single VPS.
Each family member has their own subdomain under `engineerfamily.net`.

| Subdomain | Owner | Tech |
|---|---|---|
| `engineerfamily.net` | All | Flask |
| `streamlit.engineerfamily.net` | Siddharth | Streamlit. Off by default (compose profile `streamlit`); the host 301s to the home page. |
| `umami.engineerfamily.net` | Siddharth | Umami |
| `engineerfamily.net/strelitzia/` | Siddharth | Static (nginx): Strelitzia homepage + privacy policy for its Google OAuth consent screen; `/strelitzia/dashboard/` = Strelitzia job dashboard (FastAPI + React, site sign-in via nginx `auth_request`). `strelitzia.` and `applypilot.engineerfamily.net` 301 here, `/app/…` to `/strelitzia/dashboard/…`. |
| `engineerfamily.net/wordle/` | Siddharth | Wordle solver (FastAPI, `wordle` container built from `/srv/Wordle-prod`). Public, no sign-in; nginx rate-limits `/wordle/api/` per visitor (`CF-Connecting-IP`). |

---

## Architecture

```
Internet → Cloudflare (DNS + SSL + CDN) → Hetzner VPS
                         ├── app (Flask + Gunicorn)
                         ├── streamlit (opt-in profile)
                         ├── umami (opt-in profile)
                         ├── strelitzia (job dashboard, built from /srv/Strelitzia-prod; nginx /strelitzia/dashboard/)
                         ├── wordle (Wordle solver, built from /srv/Wordle-prod; nginx /wordle/, public)
                         └── postgres-db (Postgres for umami and Strelitzia's `strelitzia` DB on 127.0.0.1:5432, see `make strelitzia-db-init`)
```

Routing for site pages is managed in Flask (`services/app/app.py`).

---

## Deploying

Releases, preprod and prod deploys, the deploy workflow and the VPS layout are in [agents/DEPLOY.md](agents/DEPLOY.md).

## Local Development

```bash
# Copy env
cp .env.example .env

# Start the Flask app (local); add COMPOSE_PROFILES=streamlit for Streamlit
make local-up

# Open home page
http://localhost:8000/

# Stop app
docker compose down
```

---

## Auth

Site-wide Google sign-in lives in the Flask app (`services/app/auth.py`), at `/auth/*`. It only knows who you are, and
signing in grants nothing by itself. What a visitor may open comes from the site permissions (`services/app/perms.py`,
edited on `/users/` by admins) and nginx enforces it (see **Site permissions** below).

| Route | What |
|---|---|
| `GET /auth/login?next=<path>` | 303 to Google (`openid email profile`, `prompt=select_account`). `next` must be a same-site path. |
| `GET /auth/callback` | Checks `state`, exchanges the code, verifies the ID token (verified email only), 303 to `next`; failures go to `next?signin=error` and store nothing. |
| `GET /auth/me` | `{"enabled", "signed_in", "email", "name"}`, `Cache-Control: no-store`. |
| `POST /auth/logout` | Clears the session, 204. |
| `GET /auth/verify?page=<key>` | For nginx `auth_request` (a 404 from outside): 204 when the visitor may open the page, with `X-Auth-Request-Access`, `-Admin` (and `-Cap-Usd` for Strelitzia), plus `X-Auth-Request-Email`, `-User` (Google `sub`) and `-Preferred-Username` (percent-encoded name) when signed in; else 401 signed out, 403 signed in. oauth2-proxy's header names. |
| `GET /auth/denied?status=401\|403` | The no-access page nginx shows on a refusal (`X-Original-URI` or `?next=` is the page asked for): 401 "Sign in to continue" with a Sign in button, 403 "You don't have access to this page. Ask an admin." |

- **Cookie** `ef_session`: Flask's signed session, `Path=/`, no `Domain` (host-only, so prod, preprod, `www` and
  `umami.` never share it), `HttpOnly`, `Secure`, `SameSite=Lax`, 30 days from sign-in. Signed with `SITE_SESSION_SECRET`.
- **Env** (each env's `.env`, passed to `app` by compose): `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (the
  "Strelitzia web" OAuth client, same Google project as the dashboard), `SITE_SESSION_SECRET` (its own value per env;
  rotating it signs everyone out). `PUBLIC_URL` is set in the compose file. Sign-in is off while `GOOGLE_CLIENT_ID` is
  empty; with it set, the app refuses to start unless the other three are set too.
- **Google**: redirect URIs `https://engineerfamily.net/auth/callback` and `https://preprod.engineerfamily.net/auth/callback`;
  the consent screen is named `engineerfamily` with privacy policy `https://engineerfamily.net/privacy`.
- **Header**: every page loads `/shared/site-header.js` (`services/shared/`, served by nginx) for the `<ef-home>` link
  top left and the `<ef-profile>` sign-in / profile / Sign out control top right. See `services/shared/README.md`.
  `node scripts/check-header-layout.mjs <base-url> [--netrc FILE]` checks the signed-in header fits on one row at 1280 and 390 px.
- Tests (dev only, no CI): `cd services/app && python -m pytest test_auth.py -q`.

### Site permissions

Every page on `engineerfamily.net` and `preprod.engineerfamily.net` needs the **Site** grant; some pages also need their
own grant (**Strelitzia** for `/strelitzia/dashboard/`, **Bracket Analyzer** for `/bracket/`). The **Everyone** row
covers signed-out visitors and anyone not on the list: on prod it starts with Site (`SITE_EVERYONE=site`), so the public
site looks unchanged; on preprod it starts empty, so preprod is sign-in-only. While no admin exists at all, everyone gets
Site, so a deploy before the DB and `.env` step (`agents/DEPLOY.md`) can't lock anyone out.

- **How**: the main vhost in `nginx.{prod,preprod}.conf` sets `auth_request /_auth_site` at server level, and each
  restricted page's location replaces it with its own (`/_auth_strelitzia`, `/_auth_bracket`). Each `/_auth_<key>` is an
  internal location proxying to `/auth/verify?page=<key>`. A 401 or 403 goes to `@denied401` / `@denied403`, which show
  `/auth/denied`. The dashboard also gets the visitor's `X-Auth-Request-Access`, `-Admin` and `-Cap-Usd`.
- **Open without Site** (`auth_request off`): `/auth/` (sign-in and the no-access page), `/privacy` and
  `/strelitzia/privacy` with its `style.css` and `favicon.svg` (Google's consent screen links them), `/healthz`,
  `/robots.txt`, `/shared/`, `/favicon.ico`, the Vite `/assets/` bundle, and the preprod `127.0.0.1` health server.
  The `/strelitzia/` about page needs Site. `nginx.local.conf` has no sign-in, so local stays ungated.
- **Adding a restricted page**: one `Page(...)` entry in `PAGES` in `services/app/perms.py` (it shows up on `/users/`),
  plus in both nginx confs one `location = /_auth_<key>` (a copy of `/_auth_bracket`) and `auth_request /_auth_<key>;`
  in the page's location. Don't use a bare `return` there: it runs before `auth_request`, so nothing is checked.

---

## Analytics

Umami is at `umami.engineerfamily.net`. It is off by default to save memory: the `umami` service sits behind a compose
profile. To run it, set `COMPOSE_PROFILES=umami` in the env's `.env` (or the shell) and redeploy. Locally that also starts
`postgres-db-local`; on the VPS `postgres-db` always runs, because the Strelitzia dashboard uses it.

This repo uses a hybrid analytics model:

- Product analytics (sessions, visitors, campaign attribution): Umami JS tracker where supported.
- Request analytics (all hostnames/services): nginx access logs in JSON.

To add tracking to a page, paste into the `<head>`:
```html
<script async src="https://umami.engineerfamily.net/script.js"
        data-website-id="YOUR_WEBSITE_ID"></script>
```
Get `YOUR_WEBSITE_ID` from the Umami dashboard after adding each site.

For the main Vite app, the tracker website ID is injected at build time from
`UMAMI_APP_ID` (mapped to Vite env `VITE_UMAMI_APP_ID` during Docker build).

Current service behavior:

- Main Flask/Vite site: Umami script is included in the Vite app entry HTML.
- Streamlit: Umami script is injected via `streamlit.components.v1` when
   `UMAMI_HOST` and `UMAMI_STREAMLIT_ID` are set.

View access logs:

```bash
docker compose logs -f nginx
```

---

## Ingress Strategy (Recommended)

Ingress is the path internet traffic takes into your VPS and containers.

Recommended pattern for this repo now:

1. Keep Cloudflare in front for DNS, TLS, and DDoS protection.
2. Expose only ports 80/443 publicly on the VPS.
3. Run a single edge reverse proxy on the VPS (Nginx).
4. Route traffic by hostname/path to containers on the internal Docker network:
   - `engineerfamily.net` -> `app:8000` (including `/auth/*` and `/privacy`)
   - `engineerfamily.net/shared/` -> static files in `services/shared/` (the shared header script)
   - `engineerfamily.net/strelitzia/` -> static files in `services/strelitzia/` (served by nginx)
   - Every page on the main host needs the Site grant, checked by nginx `auth_request` (see **Site permissions**)
   - `engineerfamily.net/strelitzia/dashboard/` -> `strelitzia:8000`, behind `auth_request` to Flask's
     `/auth/verify?page=strelitzia`: nginx sets `X-Auth-Request-{Email,User,Preferred-Username,Access,Admin,Cap-Usd}`,
     replacing any client copy, for the dashboard (`STRELITZIA_AUTH_MODE=proxy`). `/auth/verify` is a 404 from outside, and
     `strelitzia` sits only on the `dashboard` network (with `nginx` and `postgres-db`), so nothing else can reach it.
     Preprod has no basic auth: its Everyone row has no Site grant, so it is sign-in-only, and `preprod.engineerfamily.net`
     sends `X-Robots-Tag: noindex, nofollow` and a `Disallow: /` robots.txt. Ship Strelitzia trunk with `make strelitzia-deploy`
   - `www.engineerfamily.net` -> 301 to `engineerfamily.net` (one host-only `ef_session` cookie)
   - `streamlit.engineerfamily.net` -> 301 to `engineerfamily.net` while the `streamlit` profile is off
   - `umami.engineerfamily.net` -> `umami:3000`
   - `strelitzia.engineerfamily.net`, `applypilot.engineerfamily.net` -> 301 to `engineerfamily.net/strelitzia/`,
     keeping the path (`/app/…` -> `/strelitzia/dashboard/…`); on preprod `strelitzia-preprod.` 301s to
     `preprod.engineerfamily.net/strelitzia/` the same way, and `127.0.0.1:8080` answers only the dashboard health check
5. Keep app containers (`app`, `streamlit`, `umami`, `strelitzia`) off public ports in production; publish only for local development.
6. Caching: nginx sends `Cache-Control: no-cache` on `/shared/` and `/strelitzia/` (404s too), so a deploy shows at once.
   Cloudflare: Caching → Configuration → Browser Cache TTL = **Respect Existing Headers** (set 2026-10-19 by the zone owner; keep it).
   Any other value rewrites the header on files Cloudflare caches (`.js`, `.css`, `.svg`), for example to
   `max-age=14400`, and browsers keep a stale header script, or a cached 404, for 4 hours. Check from outside:
   `curl -sI https://engineerfamily.net/shared/site-header.js | grep -i cache-control` should print `no-cache`.

Why this is preferred:

- One place to manage TLS, redirects, headers, and rate limits.
- Cleaner security boundary (single public entrypoint).
- Easier migration as services grow.

## Useful Commands

```bash
make ps              # container status
make logs            # tail all logs
make restart         # rebuild + restart changed services
make preprod-deploy  # put origin/main (or ref=…) on preprod
make preprod-up      # restart preprod as checked out
make run-app         # run Flask locally without Docker
make run-streamlit   # run Streamlit locally without Docker
```
