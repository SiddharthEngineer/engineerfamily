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

## Deploying

**Production** — push to `main`:
```bash
git push origin main
```
GitHub Actions runs `.github/workflows/deploy-prod.yml` → rsync → `docker compose up -d --build`.

**Preprod** — push to `preprod`:
```bash
git push origin preprod
```
Deploys to `/srv/engineerfamily-preprod/` using the same Caddyfile as production. All subdomains are
behind basic auth at `*.preprod.engineerfamily.net`.

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
