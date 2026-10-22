# Plan: Wordle solver, part 3: serve it at engineerfamily.net/wordle/
**Status:** 🟡 Tasks 1–3 done 2026-10-22; Task 4 (interactive: /srv checkouts, preprod deploy) left for the user
**Risk:** review (compose, nginx, Makefile and scripts are high-risk paths)
**Depends on:** wordle-solver-2-web

## Goal
`https://engineerfamily.net/wordle/` (and preprod) serves the Wordle solver from a `wordle` container built from the
Wordle repo, public with no sign-in, rate-limited, linked from the home page. The user ships it like Strelitzia:
`make wordle-deploy [ref=<sha>]` for prod, `make preprod-wordle-deploy [ref=<sha>]` for preprod.

## Context
- `docker-compose.prod.yml:101-120` and `docker-compose.preprod.yml:97-115`: the `strelitzia` service built from
  `../Strelitzia-prod` / `../Strelitzia-preprod`. Mirror the build-context pattern; `wordle` needs no env, volumes, DB
  or `dashboard` network: put it on `web` only (`docker-compose.base.yml:4-6`). Add `cpus: 1.0` and `mem_limit: 1g`.
- `docker-compose.preprod.yml:15-17`: preprod nginx `depends_on` lists `strelitzia`; add `wordle` there too. Prod nginx
  doesn't list strelitzia, so don't add it in prod. `docker-compose.local.yml` stays as is (no local Wordle checkout).
- `services/nginx/nginx.prod.conf:1-3,28-39` and `nginx.preprod.conf:1-4,40-52`: top-of-file `resolver` and the
  `/strelitzia` static locations. Add `/wordle` locations next to them. Use the `set $upstream_x …; proxy_pass $upstream_x;`
  pattern (nginx starts even when the container is down, and `nginx -t` in CI needs no DNS).
- No real-IP handling exists: `$remote_addr` is a Cloudflare IP. Key the rate limit on `CF-Connecting-IP`.
- `services/nginx/nginx.preprod.conf:44-51`: preprod adds `X-Robots-Tag "noindex, nofollow"` on every location; do the same.
- `services/nginx/nginx.preprod.conf:182-205`: host-only server for health checks at `127.0.0.1:8080`; add an exact
  `location = /wordle/api/health` there, same shape.
- `Makefile:23,147-155,185-192`: `STRELITZIA_PROD_DIR`, `strelitzia-deploy`, `preprod-strelitzia-up`. Mirror them;
  also add the new targets to `.PHONY` (`Makefile:7-14`) and `help` (`Makefile:59-62,72-74`).
- `scripts/prod-changes.sh:1-60`: prints Strelitzia commits since what `/srv/Strelitzia-prod` runs; add the same for
  Wordle (`WORDLE_PROD_DIR`, dev clone `$WORDLE_DEV_DIR` default `~/src/Wordle`, branch `origin/main`); skip with a note
  when either dir is missing instead of failing.
- `services/app/vite/src/App.jsx:20-23`: the home page nav link to `/strelitzia/` (full page load, since nginx serves it).
- `agents/DEPLOY.md:95-110`: VPS layout table; `README.md:8-13,19-26`: hostname table and architecture.
- `agents/runner.toml:35-39`: preprod health URLs the runner checks after a preprod deploy.
- Gotcha: `deploy-prod` and `preprod-deploy` run `up --build` for every service, so `/srv/Wordle-prod` and
  `/srv/Wordle-preprod` must exist **before** the first deploy that contains this change, or the build fails.

## Tasks
### Task 1: Compose services
**Runs:** unattended
**Files:** docker-compose.prod.yml (modify), docker-compose.preprod.yml (modify)
**What:** `wordle` service: `build: { context: ../Wordle-prod }` (preprod: `../Wordle-preprod`),
`restart: unless-stopped`, `networks: [web]`, `cpus: 1.0`, `mem_limit: 1g`, comment block in the Strelitzia style
(where it's built from, which make target moves it). No published ports.
**Validate:** `scripts/validate.sh` → `PASS  compose preprod` and `PASS  compose prod`.
**Status:** ✅ 2026-10-22 (this commit)

### Task 2: nginx routing and rate limit
**Runs:** unattended
**Files:** services/nginx/nginx.prod.conf (modify), services/nginx/nginx.preprod.conf (modify)
**What:** at file top: `map $http_cf_connecting_ip $wordle_client { "" $binary_remote_addr; default $http_cf_connecting_ip; }`
and `limit_req_zone $wordle_client zone=wordle_api:10m rate=5r/s;`. In the main host's server block:
`location = /wordle { return 301 /wordle/; }`; `location /wordle/` → `set $upstream_wordle http://wordle:8000;
proxy_pass $upstream_wordle;` with the standard four `proxy_set_header` lines and `add_header Cache-Control "no-cache" always;`;
nested `location /wordle/api/` with `limit_req zone=wordle_api burst=10 nodelay; limit_req_status 429;`,
`proxy_read_timeout 30s;`, `client_max_body_size 16k;`, `gzip on; gzip_types application/json;` and the same proxy lines.
No `auth_request` (public). Preprod: same plus `X-Robots-Tag`, and the host-only `location = /wordle/api/health`.
**Validate:** `scripts/validate.sh` → `PASS  nginx preprod`, `PASS  nginx prod`.
**Status:** ✅ 2026-10-22 (this commit)

### Task 3: Make targets, prod-changes, home link, docs, runner health
**Runs:** unattended
**Files:** Makefile (modify), scripts/prod-changes.sh (modify), services/app/vite/src/App.jsx (modify), README.md (modify),
agents/DEPLOY.md (modify), agents/runner.toml (modify)
**What:**
- Makefile: `WORDLE_PROD_DIR ?= /srv/Wordle-prod`, `WORDLE_PREPROD_DIR ?= /srv/Wordle-preprod`.
  `wordle-deploy`: fetch, `checkout -q --detach $(or $(ref),origin/main)`, echo the commit, `$(PROD) up -d --build
  --force-recreate --no-deps wordle`. `preprod-wordle-deploy`: same on the preprod dir with `$(PREPROD)`.
  `wordle-logs`, `preprod-wordle-logs`. `.PHONY` and `help` lines. `prod-changes` passes `WORDLE_PROD_DIR` through.
- `scripts/prod-changes.sh`: a third section "Wordle: <sha>..origin/main" with PR links (`SiddharthEngineer/Wordle`).
- `App.jsx`: a "Wordle solver" nav link to `/wordle/` beside Strelitzia, with the same full-page-load comment.
- README: hostname table row for `engineerfamily.net/wordle/`, architecture line. DEPLOY.md: `/srv/Wordle-{prod,preprod}`
  rows and the deploy commands. runner.toml: health `{ url = "https://preprod.engineerfamily.net/wordle/api/health", json_ok = true }`.
**Validate:** `scripts/validate.sh` → all PASS; `make -n wordle-deploy` and `make -n preprod-wordle-deploy` print the
git and compose commands (dry run, nothing executes); `bash -n scripts/prod-changes.sh` → ok.
**Status:** ✅ 2026-10-22 (this commit). `make -n` dry runs not run: make is denied to the unattended agent; Makefile recipes checked by reading the diff

### Task 4: Create the /srv checkouts and try it on preprod
**Runs:** interactive (the user: `/srv` checkouts, `make`, preprod deploy)
**Files:** none
**What:** as the deploy user, `git clone https://github.com/SiddharthEngineer/Wordle /srv/Wordle-prod` and
`/srv/Wordle-preprod` (owner `deploy:srv`, setgid, group-writable, like the Strelitzia ones), and a dev clone in
`~/src/Wordle`. Then `make preprod-deploy ref=<PR head>` and follow the Human test steps.
**Validate:** `curl -s https://preprod.engineerfamily.net/wordle/api/health` → `{"ok":true,"words":12971}`.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes (CI runs it on the PR).
- After the preprod deploy, through Cloudflare:
  `curl -s -o /dev/null -w "%{http_code}" https://preprod.engineerfamily.net/wordle/` → `200`;
  `curl -s -o /dev/null -w "%{http_code}" https://preprod.engineerfamily.net/wordle` → `301`;
  `for i in $(seq 30); do curl -s -o /dev/null -w "%{http_code}\n" -X POST -H 'content-type: application/json' -d '{"rows":[]}' https://preprod.engineerfamily.net/wordle/api/solve; done | sort | uniq -c`
  → some `429`s alongside `200`s.

## Human test steps (preprod)
1. Open `https://preprod.engineerfamily.net/wordle/` signed out: grid, on-screen keyboard and a 12,971-word table load;
   the header shows the engineerfamily link and Sign in.
2. Type `CRANE`. Click the C tile once (yellow), twice (green), three times (black). Set any colors, press Submit:
   "N words left" drops, the next row unlocks, the table refreshes.
3. Type `ZZZZZ` and press Enter: the row shakes, "Not in word list".
4. Click a tile in the submitted row, press "Update": results change.
5. Sort by E(|v|), then "Show all": all rows appear, sorted ascending.
6. Reload: the grid comes back. Press Reset: empty grid, full list.
7. Repeat on a phone (390 px): no sideways scroll, on-screen keys work.
8. Home page `https://preprod.engineerfamily.net/` has a "Wordle solver" link that opens the page.

## Decisions
1. Path `/wordle/` on the main host, no new DNS; public, no `auth_request`.
2. Built from pinned `/srv/Wordle-{prod,preprod}` checkouts with its own deploy target, like Strelitzia, so it ships
   without an engineerfamily tag.
3. Rate limit keyed on `CF-Connecting-IP` (5 r/s, burst 10) plus CPU/memory limits, since scoring is CPU-heavy and public.
4. `wordle` sits on the `web` network only; it never sees identity headers.
5. Prod rollout stays the user's: create `/srv/Wordle-prod`, then `make tag-prod`/`deploy-prod` for nginx and compose,
   and `make wordle-deploy` for later solver updates.
