# AGENTS.md (auto-loaded every session through CLAUDE.md; keep it short)

engineerfamily: the Docker stack on the Hetzner VPS behind Cloudflare. nginx routes by hostname and path to Flask (`app`), the
Strelitzia dashboard (`engineerfamily.net/strelitzia/dashboard/`) and, behind opt-in compose profiles, Streamlit and Umami.
Layout and routing are in `README.md`; how deploys work is in `agents/DEPLOY.md`.

## Map
- `services/`: `app/` (Flask home page and site auth), `nginx/` (`nginx.{local,preprod,prod}.conf`), `strelitzia/` and
  `shared/` (static files nginx serves), `streamlit/`.
- `docker-compose.base.yml` + `docker-compose.{local,preprod,prod}.yml`; `.env.template` (the real `.env` files live in `/srv`).
- `components.toml`: the Strelitzia and Wordle tags every deploy builds (`scripts/components.py` reads it); a pin change is a PR.
- `Makefile`: dev, preprod and prod targets (they act on the `/srv` checkouts wherever make runs); `make prod-changes`.
- `scripts/`: `validate.sh`, `prod-changes.sh`, `site-version.sh` (header version), DB setup, `vps/` (deploy user and SSH hardening).
- `agents/ROADMAP.md`: the only status tracker. `agents/plans/<slug>.md`: one spec per change (`done/` holds the archive).

## Validate (run before claiming a config works)
`scripts/validate.sh`: `bash -n` on the scripts, compose `config -q` for local/preprod/prod with `.env.template`, and `nginx -t`
for each conf. CI runs the same on every PR.

## PIV loop (commands in `.claude/commands/`)
`/plan` (always with the user; sets risk) → `/implement <plan>` or `/schedule-build <slug>` (unattended on the VPS)
→ `/validate` → `/ship` (risk gate: auto-merge low, else PR on preprod). Bugs start with `/rca`.

## Deploys
- **Preprod:** `make preprod-deploy [ref=<sha|tag|origin/branch>]` on the VPS. No tag needed. Push first, because it deploys what is on GitHub.
- **Prod:** only with the user's explicit go-ahead, every time. `make prod-release [v=X.Y.Z] [dry=1]` ships the newest tag
  with its `components.toml` pins (one preview, one y/N), health-checks, then promotes the engineerfamily release and each
  child release whose pin moved. Rollback: `make deploy-prod ref=<previous tag>` (children follow its pins; promotes nothing).
  `make prod-changes` shows what will ship. `strelitzia-deploy`/`wordle-deploy` are for hand fixes only.
- After a deploy, check from outside, through Cloudflare: `curl -s -o /dev/null -w "%{http_code}" https://<host>/`. A check
  against `127.0.0.1:8080` doesn't prove the public hostname routes to the right nginx.

## Rules
- Public repo (`origin` = SiddharthEngineer/engineerfamily, base `main`, merge commits).
- Work on a branch, open a PR to `main`. Validate before claiming a config works: `scripts/validate.sh`.
- Never commit server-only files (`.env`, `services/nginx/ssl/`, `.htpasswd*`). Never print secrets.
- Never `chown`, force-push `main`, drop volumes or databases, or run as root.
- Prod is the user's: never tag, deploy or restart prod (`prod-release`, `deploy-prod`, `strelitzia-deploy`, `-p engineerfamily`).
- Make targets act on the `/srv` checkouts wherever they run. Never edit, commit or merge inside `/srv` by hand.
- Browser testing signs in only as the dev test account, never as the user's own Google account.
- When a plan task finishes: set its Status in the plan and the ROADMAP row. Git history and PRs are the changelog.
