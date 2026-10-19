# Plan: preprod without basic auth (Google sign-in is its only gate, like prod)
**Status:** ❌ Not started
**Risk:** review (nginx, compose and `scripts/validate.sh` are high-risk paths; preprod's front door changes)

## Goal
`https://preprod.engineerfamily.net/` drops its nginx basic auth, so it behaves like prod: every page opens signed out, and
the Strelitzia dashboard is gated only by Google sign-in (`auth_request`) plus the preprod invite list. Search engines are
told not to index preprod. This unblocks agent-runner's AM3: a saved browser session for the dev test account is then all the
preprod validator needs to run the signed-in test steps (no basic-auth prompt in front of Google's redirect).

## Context
- `services/nginx/nginx.preprod.conf`: `auth_basic` + `auth_basic_user_file` pairs at lines 12-13 (`/`), 26-27 (`/shared/`),
  39-40 (`/strelitzia/`), 68-69 (`/strelitzia/dashboard/`) and 184-185 (the `127.0.0.1` health server). Prod
  (`nginx.prod.conf`) has none since #31; mirror it.
- `docker-compose.preprod.yml:15`: mounts `services/nginx/.htpasswd`. `scripts/validate.sh:42-48` makes a temp htpasswd only
  because preprod's conf names one.
- Gotcha: nginx `add_header` in a location **replaces** every server-level `add_header`. `/shared/` and `/strelitzia/` set
  `Cache-Control`, so a server-level `X-Robots-Tag` must be repeated in those two locations (and in `/healthz` blocks it is
  irrelevant). Put `add_header X-Robots-Tag "noindex, nofollow" always;` at server level in the `preprod.engineerfamily.net`
  block and in each location there that has its own `add_header`.
- Text that still says preprod has basic auth: `README.md:133`, `.env.template:48-49`, `scripts/setup-vps.sh:54-55`.
  Strelitzia's `agents/DEPLOY.md:131,164` and agent-runner's `README.md`/`prompts/preprod-check.md` are other repos: list
  them in the PR body as follow-ups, don't edit them here.
- The runner's netrc (`PREPROD_NETRC`) keeps working: curl and Playwright only send credentials when challenged.
- Nothing on the VPS needs deleting: the untracked `/srv/engineerfamily-preprod/services/nginx/.htpasswd` just goes unused.

## Tasks
### Task 1: nginx and compose
**Runs:** unattended
**Files:** services/nginx/nginx.preprod.conf (modify), docker-compose.preprod.yml (modify), scripts/validate.sh (modify)
**What:** Delete all five `auth_basic`/`auth_basic_user_file` pairs and the comments that mention basic auth (keep the
`satisfy`-free `auth_request` on the dashboard as it is). Add the `X-Robots-Tag` header as in Context, and a
`location = /robots.txt { add_header Content-Type text/plain; add_header X-Robots-Tag "noindex, nofollow" always; return 200 "User-agent: *\nDisallow: /\n"; }`
in the `preprod.engineerfamily.net` server. Drop the `.htpasswd` volume line, and the htpasswd temp file and its `-v` mount in
`validate.sh`.
**Validate:** `scripts/validate.sh` → passes. `grep -c auth_basic services/nginx/nginx.preprod.conf` → `0`.
**Status:** ❌

### Task 2: docs
**Runs:** unattended
**Files:** README.md (modify), .env.template (modify), scripts/setup-vps.sh (modify)
**What:** Say preprod has no basic auth (Google sign-in gates the dashboard, robots are told noindex). Remove the htpasswd
instructions from `.env.template` and `setup-vps.sh`.
**Validate:** `scripts/validate.sh` passes; `grep -rn -i 'htpasswd\|basic auth' README.md .env.template scripts/` → no lines about preprod.
**Status:** ❌

### Task 3: tracking
**Runs:** unattended
**Files:** agents/ROADMAP.md (modify), agents/plans/preprod-open.md (modify)
**What:** Task statuses here; E2's ROADMAP status to `✅ (#<pr>)`.
**Validate:** `scripts/validate.sh` passes.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes; CI is green.
- On preprod (no credentials, through Cloudflare):
  `curl -s -o /dev/null -w '%{http_code}' https://preprod.engineerfamily.net/` → `200`;
  same for `/strelitzia/` and `/shared/site-header.js` → `200`;
  `curl -sI https://preprod.engineerfamily.net/ | grep -i x-robots-tag` → `noindex, nofollow`;
  `curl -s https://preprod.engineerfamily.net/robots.txt` → `Disallow: /`;
  `curl -s https://preprod.engineerfamily.net/strelitzia/dashboard/api/health` → JSON with `"ok": true`.
  `curl -s -o /dev/null -w '%{http_code}' https://preprod.engineerfamily.net/strelitzia/dashboard/api/jobs` → `401` (signed out).

## Human test steps (preprod)
1. In a private window open `https://preprod.engineerfamily.net/`: the home page loads with no password prompt, header shows Sign in.
2. Open `/strelitzia/dashboard/`: the "Sign in to see your jobs" card, no password prompt.
3. Sign in as the dev test account: the dashboard opens with the seeded jobs.
4. Then do agent-runner AM3 (save that session for the validator).

## Decisions
1. Preprod matches prod's gate (Google sign-in only); preprod data is the fake seed (`scripts/seed_preprod.py`), so being
   reachable signed out exposes nothing new (user, 2026-10-19).
2. Preprod says `noindex` (header + robots.txt) so it never shows up in search next to prod.
3. Done before AM3 so the saved session is the only thing the validator's browser needs (user, 2026-10-19).
