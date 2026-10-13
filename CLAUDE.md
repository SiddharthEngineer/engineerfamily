# CLAUDE.md (auto-loaded every session; keep it short)

engineerfamily: the Docker stack on the Hetzner VPS behind Cloudflare. nginx routes by hostname to Flask (`app`), Streamlit,
Umami, BookStack and the Strelitzia dashboard. Layout and routing are in `README.md`.

## Deploys
- **Preprod:** `make preprod-deploy [ref=<sha|tag|origin/branch>]` on the VPS. No tag needed. Push first, because it deploys what is on GitHub.
- **Prod:** only with the user's explicit go-ahead, every time. `make tag-prod v=X.Y.Z`, then `make deploy-prod ref=vX.Y.Z`.
  Rollback: `make deploy-prod ref=<previous tag>`. The Strelitzia dashboard ships on its own with `make strelitzia-deploy [ref=<sha>]`.
- Make targets act on the `/srv` checkouts wherever they run. Never edit, commit or merge inside `/srv` by hand.
- After a deploy, check from outside, through Cloudflare: `curl -s -o /dev/null -w "%{http_code}" https://<host>/`. A check
  against `127.0.0.1:8080` doesn't prove the public hostname routes to the right nginx.

## Rules
- Work on a branch, open a PR to `main`. Validate before claiming a config works:
  `docker compose --env-file /srv/engineerfamily-<env>/.env -f docker-compose.base.yml -f docker-compose.<env>.yml config -q`
  and `nginx -t` in an `nginx:alpine` container with the conf mounted.
- Never commit server-only files (`.env`, `services/nginx/ssl/`, `.htpasswd*`). Never print secrets.
- Never `chown`, force-push `main`, drop volumes or databases, or run as root.
