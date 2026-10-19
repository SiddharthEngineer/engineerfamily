# Engineer Family Website

Personal family website running on a single VPS.
Each family member has their own subdomain under `engineerfamily.net`.

| Subdomain | Owner | Tech |
|---|---|---|
| `engineerfamily.net` | All | Flask |
| `streamlit.engineerfamily.net` | Siddharth | Streamlit. Off by default (compose profile `streamlit`); the host 301s to the home page. |
| `umami.engineerfamily.net` | Siddharth | Umami |
| `engineerfamily.net/strelitzia/` | Siddharth | Static (nginx): Strelitzia homepage + privacy policy for its Google OAuth consent screen; `/strelitzia/dashboard/` = Strelitzia job dashboard (FastAPI + React, Google sign-in). `strelitzia.` and `applypilot.engineerfamily.net` 301 here, `/app/…` to `/strelitzia/dashboard/…`. |

---

## Architecture

```
Internet → Cloudflare (DNS + SSL + CDN) → Hetzner VPS
                         ├── app (Flask + Gunicorn)
                         ├── streamlit (opt-in profile)
                         ├── umami (opt-in profile)
                         ├── strelitzia (job dashboard, built from /srv/Strelitzia-prod; nginx /strelitzia/dashboard/)
                         └── postgres-db (Postgres for umami and Strelitzia's `strelitzia` DB on 127.0.0.1:5432, see `make strelitzia-db-init`)
```

Routing for site pages is managed in Flask (`services/app/app.py`).

---

## Release And Deployment Model

This repo uses four branch/tag concepts:

1. `main`
   - Ongoing development and PR merges.

2. `release-v<major>.<minor>`
   - Minor-line release branches (examples: `release-v1.0`, `release-v2.7`).
   - Created automatically when first tag for a minor line appears.

3. Release tags
   - Production tags: `v<major>.<minor>.<patch>` (example: `v1.2.3`).
   - Preprod tags: `v<major>.<minor>.<patch>-preprod` (example: `v1.2.3-preprod`).

4. Deployment state branches
   - `prod`: always points to what is deployed in production.
   - `preprod`: points to the last *tag* deploy to preprod. `make preprod-deploy` (below) doesn't move it, so
     `git -C /srv/engineerfamily-preprod log -1` is the source of truth for what preprod runs.

### Tagging Rules

Use Make targets to create tags and keep release branches in sync:

```bash
make tag-preprod v=1.2.3
make tag-prod v=1.2.3
```

Enforced policy:

1. Tags for a minor line must be created from `main` or the matching `release-v<major>.<minor>` branch.
2. If `release-v<major>.<minor>` is ahead of `main`, tagging from `main` fails.
3. If tag is created from `main`, `main` is merged into the release branch.
4. If tag is created from release branch, release branch is aligned to latest tag in that minor line.

Validation/sync logic lives in:

- `scripts/release_branch_sync.sh`

## Deploying

### Preprod Deploy (everyday: no tag)

Run on the VPS, from any directory (e.g. the dev clone):

```bash
make preprod-deploy                     # origin/main
make preprod-deploy ref=origin/my-branch # a pushed branch, before merging
make preprod-deploy ref=<sha|tag>
```

It checks that commit out in `/srv/engineerfamily-preprod`, rebuilds the stack (`up -d --build --remove-orphans`) and
reloads nginx. These are the same steps the deploy workflow runs, minus the tag and the GitHub round-trip. Push the commit first, because it
deploys what is on GitHub. Preprod tags (`make tag-preprod` + `make deploy-preprod`) are optional, for a release candidate you
want on record.

### Prod Deploy (tag + workflow)

Prod deploys are always a tag, and two separate steps (tagging alone deploys nothing):

```bash
make tag-prod v=1.2.3          # validate-release-tagging, sync-release-branch, then tag v1.2.3 and push it
make deploy-prod ref=v1.2.3    # gh workflow run deploy.yml -f environment=prod -f ref=v1.2.3
```

Roll back with `make deploy-prod ref=<previous tag>`. The preprod equivalents are `make tag-preprod v=1.2.3` and
`make deploy-preprod ref=v1.2.3-preprod`.

### How the workflow works

1. Resolves `ref` as a tag or branch commit on origin.
2. Force-resets the deployment state branch (`preprod` or `prod`) to that commit.
3. SSHs into the VPS, pulls the updated branch, rebuilds containers, and reloads nginx.

---

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

Site-wide Google sign-in lives in the Flask app (`services/app/auth.py`), at `/auth/*`. It only knows who you are; every
page stays open to signed-out visitors, and signing in grants nothing by itself. Who may use the Strelitzia dashboard
stays in Strelitzia's own `users` table (owner + invites).

| Route | What |
|---|---|
| `GET /auth/login?next=<path>` | 303 to Google (`openid email profile`, `prompt=select_account`). `next` must be a same-site path. |
| `GET /auth/callback` | Checks `state`, exchanges the code, verifies the ID token (verified email only), 303 to `next`; failures go to `next?signin=error` and store nothing. |
| `GET /auth/me` | `{"enabled", "signed_in", "email", "name"}`, `Cache-Control: no-store`. |
| `POST /auth/logout` | Clears the session, 204. |
| `GET /auth/verify` | For nginx `auth_request`: 204, with `X-Auth-Request-Email`, `X-Auth-Request-User` (Google `sub`) and `X-Auth-Request-Preferred-Username` (percent-encoded name) only when signed in. oauth2-proxy's header names. |

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
- Tests (dev only, no CI): `cd services/app && python -m pytest test_auth.py -q`.

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
   - `engineerfamily.net/strelitzia/dashboard/` -> `strelitzia:8000` (no basic auth: the app has its own Google sign-in,
     while preprod keeps basic auth; ship Strelitzia trunk with `make strelitzia-deploy`)
   - `streamlit.engineerfamily.net` -> 301 to `engineerfamily.net` while the `streamlit` profile is off
   - `umami.engineerfamily.net` -> `umami:3000`
   - `strelitzia.engineerfamily.net`, `applypilot.engineerfamily.net` -> 301 to `engineerfamily.net/strelitzia/`,
     keeping the path (`/app/…` -> `/strelitzia/dashboard/…`)
5. Keep app containers (`app`, `streamlit`, `umami`, `strelitzia`) off public ports in production; publish only for local development.

Why this is preferred:

- One place to manage TLS, redirects, headers, and rate limits.
- Cleaner security boundary (single public entrypoint).
- Easier migration as services grow.

## VPS Layout

| Path | Role |
|---|---|
| `~dev/src/{engineerfamily,Strelitzia,…}` | Development clones. All editing and commits happen here. |
| `/srv/engineerfamily-prod` | Prod checkout (branch `prod`, compose project `engineerfamily`). |
| `/srv/engineerfamily-preprod` | Preprod checkout (branch `preprod`, compose project `engineerfamily-preprod`, port 8080). |
| `/srv/Strelitzia-prod` | Prod dashboard build context, detached at a trunk commit (`make strelitzia-deploy`). |
| `/srv/Strelitzia-preprod` | Preprod dashboard build context, moved to review-PR heads by Strelitzia's `scripts/agent/preprod.sh`. |

`/srv` checkouts are `deploy:srv`, setgid and group-writable, and are never edited by hand. Compose project names are
pinned with `-p` (Makefile, deploy script) and `COMPOSE_PROJECT_NAME` in each checkout's `.env`, so a directory rename
never changes container or volume names.

Every prod and preprod `make` target acts on these `/srv` checkouts, so it can be run from the dev clone.
`make up` in `~/src/engineerfamily` restarts what is deployed in `/srv/engineerfamily-prod`, not your local edits.
Edits reach preprod with `make preprod-deploy` and prod with `make tag-prod` + `make deploy-prod`, or for
Strelitzia with `make strelitzia-deploy`. Use `make local-up` to run the dev tree.

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
