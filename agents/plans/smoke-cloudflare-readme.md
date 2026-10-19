# Plan: README records the Cloudflare cache setting (smoke test, low)
**Status:** ❌ Not started
**Risk:** low (docs only; auto-merges on green CI, user 2026-10-19)
**Depends on:** the agent-runner cutover (agent-runner ROADMAP AM5)

## Goal
README's caching step still calls Cloudflare's Browser Cache TTL a manual step to do. The user set it to "Respect Existing Headers"
on 2026-10-19. Record that. This is also the agent-runner design's Rollout step 6 `low` smoke test for this repo: implementer PR →
merged after green CI, no validator run.

## Tasks
### Task 1: README caching step
**Runs:** unattended
**Files:** README.md (modify)
**What:** In step 6 ("Caching"), replace "**Manual Cloudflare step (zone owner):** Caching → Configuration → Browser Cache TTL =
**Respect Existing Headers**." with "Cloudflare: Caching → Configuration → Browser Cache TTL = **Respect Existing Headers** (set
2026-10-19 by the zone owner; keep it)." Keep the rest of the step, including the outside check. Change nothing else.
**Validate:** `scripts/validate.sh` → all PASS. `grep -n "Manual Cloudflare step" README.md` → no match.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes.

## Human test steps (preprod)
None (low risk).
