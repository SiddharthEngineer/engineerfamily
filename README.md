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

Deploys are triggered via Make targets, which create/push a tag and then invoke `gh workflow run` to dispatch `.github/workflows/deploy.yml` with explicit `environment` and `ref` inputs.

### Preprod Deploy

```bash
make tag-preprod v=1.2.3
```

This runs the following steps:

1. `validate-release-tagging` — policy gate (must be on main or release branch).
2. `sync-release-branch` — merges origin/main into release branch if needed.
3. `git tag -f v1.2.3-preprod` — creates or overwrites the local tag.
4. `git push origin v1.2.3-preprod --force` — pushes the tag to remote.
5. `gh workflow run deploy.yml --ref main -f environment=preprod -f ref=v1.2.3-preprod` — triggers the deploy workflow.

### Prod Deploy

```bash
make tag-prod v=1.2.3
```

Same flow as preprod but pushes a prod tag (`v1.2.3`) and triggers the workflow with `environment=prod`.

### How the workflow works

1. Resolves `ref` as a tag or branch commit on origin.
2. Force-resets the deployment state branch (`preprod` or `prod`) to that commit.
3. SSHs into the VPS, pulls the updated branch, rebuilds containers, and reloads nginx.

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
   - `engineerfamily.net` -> `app:8000`
   - `streamlit.engineerfamily.net` -> `streamlit:8501`
   - `umami.engineerfamily.net` -> `umami:3000`
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
