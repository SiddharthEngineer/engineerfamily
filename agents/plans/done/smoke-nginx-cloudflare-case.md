# Plan: nginx comments use Cloudflare's setting name (smoke test, review)
**Status:** ✅ Done 2026-10-19
**Risk:** review (touches services/nginx/*)
**Depends on:** engineerfamily#47 and the matching agent-runner/Strelitzia validator-settings fixes (merged, v0.1.3 installed)

## Goal
The `/shared/` comments in both nginx configs spell the Cloudflare setting "Respect existing headers"; the README and
Cloudflare's UI say "Respect Existing Headers" (the PR #46 validator noted it). Match the UI. Comments only.
This re-runs the agent-runner design's Rollout step 6 `review` smoke test, which PR #46 couldn't finish (its validator couldn't
record a verdict): validator review → preprod deploy (`make preprod-deploy ref=<sha>`) → preprod-stage checklist comment →
validator approves → the manager merges → the preprod lock releases and preprod is back on `main`.

## Tasks
### Task 1: comment wording
**Runs:** unattended
**Files:** services/nginx/nginx.preprod.conf (modify), services/nginx/nginx.prod.conf (modify)
**What:** In each file's `/shared/` comment, replace `"Respect existing headers"` with `"Respect Existing Headers"`. Nothing else.
**Validate:** `scripts/validate.sh` → all PASS (includes `nginx -t` for both envs). `git diff -U0 | grep '^[-+] ' | grep -v '^[-+] *#'` → no output.
**Status:** ✅ 2026-10-19 (this commit)

## Validation
- `scripts/validate.sh` passes.

## Human test steps (preprod)
1. `curl -sI --netrc-file <netrc> https://preprod.engineerfamily.net/shared/site-header.js | grep -i cache-control` → `no-cache`.
2. `https://preprod.engineerfamily.net/` loads, with the header (home link, Sign in).
