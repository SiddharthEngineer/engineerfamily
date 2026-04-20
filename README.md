# Engineer Family Website

Personal family website running on a single VPS.
Each family member has their own subdomain under `engineerfamily.net`.

| Subdomain | Owner | Tech |
|---|---|---|
| `engineerfamily.net` | All | Flask |
| `streamlit.engineerfamily.net` | Siddharth | Streamlit |
| `bookstack.engineerfamily.net` | Nivi | BookStack |
| `umami.engineerfamily.net` | Siddharth | Umami |

---

## Architecture

```
Internet → Cloudflare (DNS + SSL + CDN) → Hetzner VPS
                         ├── app (Flask + Gunicorn)
                         ├── streamlit
                         ├── umami
                         └── analytics (Postgres)
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
   - `preprod`: always points to what is deployed in preprod.

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

### Preprod Deploy (`.github/workflows/deploy-preprod.yml`)

Triggers:

1. Push a preprod tag like `v1.2.3-preprod`.
2. Manual run with `ref` (tag or branch).

Behavior:

1. If trigger is a preprod tag:
   - Derives release branch from tag minor line.
   - Verifies tag is reachable from that release branch.
   - Force-resets remote `preprod` branch to the resolved tag commit.
2. If trigger is manual `ref`:
   - Resolves `ref` as tag or branch commit.
   - Force-resets remote `preprod` branch to that commit.
3. VPS deploy then checks out/reset to `origin/preprod` in `/srv/engineerfamily-preprod` and runs preprod compose.

Example:

```bash
git tag v1.2.3-preprod
git push origin v1.2.3-preprod
```

### Prod Deploy (`.github/workflows/deploy-prod.yml`)

Triggers:

1. Push a prod tag like `v1.2.3`.
2. Manual run with required `tag` input.

Behavior:

1. Validates tag format `v<major>.<minor>.<patch>`.
2. Derives release branch from tag minor line.
3. Verifies the tag exists and is reachable from that release branch.
4. Force-resets remote `prod` branch to the tag commit.
5. VPS deploy then checks out/reset to `origin/prod` in `/srv/engineerfamily` and runs prod compose.

Example:

```bash
git tag v1.2.3
git push origin v1.2.3
```

---

## Local Development

```bash
# Copy env
cp .env.example .env

# Start Flask app + Streamlit (local)
docker compose --profile local up -d --build app streamlit

# Open home page
http://localhost:8000/

# Streamlit (linked from nav)
http://localhost:8501/

# Stop app
docker compose down
```

---

## Analytics

Umami is at `umami.engineerfamily.net`.

This repo uses a hybrid analytics model:

- Product analytics (sessions, visitors, campaign attribution): Umami JS tracker where supported.
- Request analytics (all hostnames/services): Caddy access logs in JSON.

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
docker compose logs -f caddy
```

---

## Ingress Strategy (Recommended)

Ingress is the path internet traffic takes into your VPS and containers.

Recommended pattern for this repo now:

1. Keep Cloudflare in front for DNS, TLS, and DDoS protection.
2. Expose only ports 80/443 publicly on the VPS.
3. Run a single edge reverse proxy on the VPS (Nginx, Traefik, or Caddy).
4. Route traffic by hostname/path to containers on the internal Docker network:
   - `engineerfamily.net` -> `app:8000`
   - `umami.engineerfamily.net` -> `umami:3000`
   - `analytics.engineerfamily.net` -> `umami:3000` (alias)
   - `suryan.engineerfamily.net` or `/suryan` -> `streamlit:8501`
5. Keep app containers (`app`, `streamlit`, `umami`) off public ports in production; publish only for local development.

Why this is preferred:

- One place to manage TLS, redirects, headers, and rate limits.
- Cleaner security boundary (single public entrypoint).
- Easier migration as services grow.

## Useful Commands

```bash
make ps              # container status
make logs            # tail all logs
make restart         # rebuild + restart changed services
make preprod-up      # start preprod
make run-app         # run Flask locally without Docker
make run-streamlit   # run Streamlit locally without Docker
```
