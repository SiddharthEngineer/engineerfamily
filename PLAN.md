Migration Plan: Caddy → Nginx
Architecture
LOCAL DEVELOPMENT:
  Browser → /etc/hosts (*.engineerfamily.test → 127.0.0.1)
  → nginx container (port 80/443)
  → app:8000 / streamlit:8501

VPS PRODUCTION:
  Browser → Cloudflare (TLS termination, Full mode)
  → Cloudflare Origin Rules route by hostname to port 80
  → nginx container (port 80) in prod Docker Compose stack
  → app:8000 / streamlit:8501 / umami:3000

VPS PREPROD:
  Browser → Cloudflare (TLS termination, Full mode)
  → Cloudflare Origin Rules route by hostname to port 8080
  → nginx container (port 8080) in preprod Docker Compose stack
  → app-preprod:8000 / streamlit-preprod:8501
  → basic auth on preprod endpoints
Each stack is a fully independent Docker Compose project with its own nginx, services, and network. No shared dependencies.
Files to create/modify
#	File	Action
1	services/nginx/nginx.local.conf	Create - Local dev nginx config routing .test domains
2	services/nginx/nginx.prod.conf	Create - Prod nginx config routing prod domains
3	services/nginx/nginx.preprod.conf	Create - Preprod nginx config routing preprod domains + basic auth
4	docker-compose.yml	Modify - Replace caddy service with nginx (prod profile); add nginx to local profile
5	docker-compose.preprod.yml	Modify - Add independent nginx-preprod service on port 8080
6	.env.template	Modify - Remove CADDY_ADMIN_HASH, plaintextpassword; add NGINX_BASIC_AUTH_PW
7	Makefile	Modify - Update targets for nginx
8	scripts/setup-vps.sh	Modify - Remove Caddy references; add Cloudflare Origin Rules instructions
9	deploy-prod.yml	Modify - Replace Caddy check/reload with nginx reload
10	deploy-preprod.yml	Modify - Remove Caddyfile sync; add nginx-preprod reload
11	services/caddy/Caddyfile	Delete
What you (the user) need to do manually
1. /etc/hosts on your Mac -- add these lines:
127.0.0.1 engineerfamily.test
127.0.0.1 streamlit.engineerfamily.test
127.0.0.1 analytics.engineerfamily.test
127.0.0.1 bookstack.engineerfamily.test
2. Cloudflare Origin Rules (3 rules):
- Rule 1: http.host eq "preprod.engineerfamily.net" or http.host eq "preprod-streamlit.engineerfamily.net" or http.host eq "streamlit-preprod.engineerfamily.net" → Set origin port to 8080
- Rule 2: http.host eq "engineerfamily.net" or http.host eq "www.engineerfamily.net" or http.host eq "streamlit.engineerfamily.net" or http.host eq "analytics.engineerfamily.net" or http.host eq "umami.engineerfamily.net" → Set origin port to 80 (this is the default, may not even need a rule)
3. Generate basic auth password hash for preprod (run on VPS):
docker run --rm httpd:2.4-alpine htpasswd -nb admin 'yourpassword'
Store the output in .env as NGINX_BASIC_AUTH_PW.
4. On the VPS: Each deploy directory (/srv/engineerfamily and /srv/engineerfamily-preprod) will contain its own nginx config and Docker Compose setup. No Caddy containers remain.
Key design decisions
- Cloudflare Full mode: nginx listens on plain HTTP (port 80 / 8080). Cloudflare handles TLS.
- Preprod basic auth: nginx auth_basic with htpasswd, same concept as Caddy's basicauth.
- No shared Docker network: each stack is fully isolated. Preprod cannot reach prod containers and vice versa.
- nginx config is baked into the image: Each stack mounts its own nginx.conf from the repo.
- Health checks: nginx configs include a /healthz endpoint for Docker healthchecks.