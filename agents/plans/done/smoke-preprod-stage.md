# Plan: preprod nginx config says who deploys it (smoke test, review)
**Status:** ✅ Done
**Risk:** review (touches services/nginx/*)
**Depends on:** agent-runner v0.1.4 installed (preprod-stage fixes, agent-runner #61)

## Goal
`nginx.preprod.conf` doesn't say that preprod also runs PR heads deployed by the shared agent-runner. Add one comment line. This is also
the full `review` smoke test, which hasn't run end to end yet (on #49 the preprod stage couldn't run its steps): validator review →
preprod deploy (`make preprod-deploy ref=<sha>`) → the validator runs the steps below on preprod and posts a checklist comment →
the manager merges → the preprod lock releases and preprod is back on `main`.

## Tasks
### Task 1: comment line
**Runs:** unattended
**Files:** services/nginx/nginx.preprod.conf (modify)
**What:** Insert one line at the top of the file, before `resolver`:
`# Preprod: main by default; the agent-runner's preprod lock deploys one PR head at a time here (make preprod-deploy ref=<sha>).`
Nothing else.
**Validate:** `scripts/validate.sh` → all PASS (includes `nginx -t`). `git diff -U0 | grep '^[-+] ' | grep -v '^[-+] *#'` → no output.
**Status:** ✅ 2026-10-19 (this commit)

## Validation
- `scripts/validate.sh` passes.

## Human test steps (preprod)
1. `curl -sI --netrc-file "$PREPROD_NETRC" https://preprod.engineerfamily.net/shared/site-header.js | grep -i cache-control` → `no-cache`.
2. `https://preprod.engineerfamily.net/` in the browser: the home page shows "engineerfamily", "Signing in with Google" and the header
   (home link top left, "Sign in" top right).
3. `curl -s -o /dev/null -w '%{http_code}' --netrc-file "$PREPROD_NETRC" https://preprod.engineerfamily.net/strelitzia/` → `200`.
