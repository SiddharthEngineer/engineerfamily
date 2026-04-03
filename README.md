# Engineer Family Website

Personal family website running on a single Hetzner VPS (~$6 total).
Each family member has their own subdomain under `engineerfamily.net`.

| Subdomain | Owner | Tech |
|---|---|---|
| `siddharth.engineerfamily.net` | Siddharth | Flask |
| `shivam.engineerfamily.net` | Shivam | JavaScript |
| `suryan.engineerfamily.net` | Suryan | Streamlit |
| `nivi.engineerfamily.net` | Nivi | Ghost CMS |
| `analytics.engineerfamily.net` | Siddharth | Umami |

---

## Architecture

```
Internet → Cloudflare (DNS + SSL + CDN) → Hetzner VPS
                                              └── Caddy (reverse proxy)
                                                    ├── siddharth → Django container
                                                    ├── suryan    → Streamlit container
                                                    ├── shivam    → Static files
                                                    ├── nivi       → Ghost container
                                                    └── analytics → Umami container
```

---

## First-time VPS Setup

1. Provision a Hetzner CX22 (Ubuntu 24.04, ~$5.59). Note the IP address.

2. SSH in as root and run the setup script:
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB/engineerfamily/main/scripts/setup-vps.sh)
   ```

3. Generate your GitHub Actions SSH keypair:
   ```bash
   ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/engineerfamily_deploy
   ```
   - Add the **public key** (`~/.ssh/engineerfamily_deploy.pub`) to `/home/deploy/.ssh/authorized_keys` on the VPS.
   - Add the **private key** as a GitHub Actions secret named `VPS_SSH_KEY`.

4. Add these GitHub Actions secrets (Settings → Secrets → Actions):
   - `VPS_SSH_KEY` — your deploy private key
   - `VPS_HOST` — your VPS IP address

5. Copy `.env.example` to `.env`, fill in all values, and upload to the VPS:
   ```bash
   scp .env deploy@YOUR_VPS_IP:/srv/engineerfamily/.env
   ```

6. Point your domain's nameservers to Cloudflare. In Cloudflare DNS, add:
   ```
   A   engineerfamily.net          → YOUR_VPS_IP
   A   *.engineerfamily.net        → YOUR_VPS_IP   (wildcard)
   A   *.preprod.engineerfamily.net → YOUR_VPS_IP
   ```

---

## Release And Deployment Model

This repo uses four branch/tag concepts:

1. `main`
   - Ongoing development and PR merges.

2. `release-v<major>.<minor>`
   - Minor-line release branches (examples: `release-v1.0`, `release-v12.20`).
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

# Start everything
make up

# Tail logs
make logs
```

---

## Adding a New Family Member

1. Add a service block to `docker-compose.yml`.
2. Add a routing block to `caddy/Caddyfile`.
3. Add `subdomain.engineerfamily.net → YOUR_VPS_IP` in Cloudflare DNS.
4. Create `services/newperson/` with a Dockerfile or use a pre-built image.

---

## Analytics

Umami is at `analytics.engineerfamily.net` (password protected).

To add tracking to a page, paste into the `<head>`:
```html
<script async src="https://analytics.engineerfamily.net/script.js"
        data-website-id="YOUR_WEBSITE_ID"></script>
```
Get `YOUR_WEBSITE_ID` from the Umami dashboard after adding each site.

---

## Generating a Caddy Basic Auth Password Hash

```bash
make hash-password
```
Paste the output into `caddy/Caddyfile` replacing `$2a$14$REPLACE_WITH_HASHED_PASSWORD`.

---

## Useful Commands

```bash
make ps              # container status
make logs            # tail all logs
make restart         # rebuild + restart changed services
make preprod-up      # start preprod
make hash-password   # generate basic auth hash
```
