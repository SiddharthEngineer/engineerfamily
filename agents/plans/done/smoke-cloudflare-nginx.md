# Plan: nginx comments record the Cloudflare cache setting (smoke test, review)
**Status:** ✅ Done (2026-10-19)
**Risk:** review (touches services/nginx/*)
**Depends on:** smoke-cloudflare-readme

## Goal
The `/shared/` comments in both nginx configs say Cloudflare's Browser Cache TTL "must be" Respect Existing Headers. The user set it
on 2026-10-19. Reword the comment only; no directive changes. This is also the agent-runner design's Rollout step 6 `review` smoke
test: validator review → preprod deploy (`make preprod-deploy ref=<sha>`) → preprod-stage checklist comment → validator approves →
the manager merges → the preprod lock releases and preprod is back on `main`.

## Tasks
### Task 1: comment wording
**Runs:** unattended
**Files:** services/nginx/nginx.preprod.conf (modify), services/nginx/nginx.prod.conf (modify)
**What:** In each file's `/shared/` comment, replace "Cloudflare's Browser Cache TTL must be "Respect existing headers", or it
rewrites" with "Cloudflare's Browser Cache TTL is "Respect existing headers" (set 2026-10-19); any other value rewrites", rewrapping
the comment lines to stay under 130 characters. Comments only: `git diff` must show no change to a line that isn't a `#` comment.
**Validate:** `scripts/validate.sh` → all PASS (includes `nginx -t` for both envs). `git diff -U0 | grep '^[-+] ' | grep -v '^[-+] *#'` → no output.
**Status:** ✅ 2026-10-19 (63a2572)

## Validation
- `scripts/validate.sh` passes.

## Human test steps (preprod)
1. `curl -sI --netrc-file <netrc> https://preprod.engineerfamily.net/shared/site-header.js | grep -i cache-control` → `no-cache`.
2. `https://preprod.engineerfamily.net/` loads, with the header (home link, Sign in).
