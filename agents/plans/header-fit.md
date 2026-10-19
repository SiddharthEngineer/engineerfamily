# Plan: the signed-in header fits on one row on the Strelitzia static pages (R43 follow-up)
**Status:** ❌ Not started
**Risk:** review (changes the shared header and public pages; the validator checks it on preprod)
**Depends on:** -

## Goal
Strelitzia R43's prod checks (2026-10-19) found the signed-in header wraps on `/strelitzia/` and `/strelitzia/privacy`. db17e0a
widened the column to 760 px, but it still wraps. Measured on preprod on 2026-10-19 (Playwright, `/auth/me` faked as signed in):
- 1280 px: home link top 48, profile top 96, so the profile is on a second row. The 728 px content box needs about 729 px: home 176 +
  brand ~120 + nav 245 + profile 140 (the CSS comment assumed ~130) + 3 gaps of 16.
- 390 px: the profile still gets its own row: home 176 + brand icon ~28 + profile 140 + gaps don't fit in 358 px.
- `/` and `/games/` fit at both widths (profile at the same top as the home link, no sideways scroll).

## Context
- `services/strelitzia/style.css:17-30`: the column width, the header flex row and the 760/480 px media queries.
- `services/shared/site-header.js`: `<ef-home>` and `<ef-profile>` render in Shadow DOM with fixed styles, so page CSS can only size
  the host elements. A compact mode has to come from the component (e.g. a `compact` attribute, or a container/`matchMedia` rule
  inside its own `<style>`) that shows the home dot without the "engineerfamily" text and the initials without "Sign out" text
  squeezing. Keep both controls reachable (Sign out stays one tap away, in the menu if it leaves the row).
- `/auth/me` answers `{"enabled": true, "signed_in": true, "email": …, "name": …}` when signed in.
- The dashboard has its own top bar (Strelitzia `dashboard/src/styles.css` `.site-topbar`); it isn't in scope here.

## Tasks
### Task 1: a layout check
**Runs:** unattended
**Files:** scripts/check-header-layout.mjs (new), README.md (modify)
**What:** A Playwright script (`node scripts/check-header-layout.mjs <base-url> [--netrc FILE]`) that, with `/auth/me` routed to a
signed-in answer, loads `/`, `/games/`, `/strelitzia/` and `/strelitzia/privacy` at 1280 and 390 px and checks: `ef-home` and
`ef-profile` have the same top (±4 px), the page's `scrollWidth` equals the viewport width, the Sign out control's right edge is inside
the viewport, and the page's nav is at least 100 px wide. Prints one line per page/width and exits 1 on any failure. README: one line.
It uses whatever Playwright `npx` resolves; if no browser is installed it says so and exits 2.
**Validate:** against `https://preprod.engineerfamily.net` (netrc from `$PREPROD_NETRC`) it fails on the two Strelitzia pages at both
widths and passes on `/` and `/games/`, matching the Goal.
**Status:** ✅ 2026-10-19 (Task 1 commit)

### Task 2: fit the row
**Runs:** unattended
**Files:** services/strelitzia/style.css (modify), services/strelitzia/index.html (modify), services/strelitzia/privacy.html
(modify), services/shared/site-header.js (modify, only if a compact mode is needed)
**What:** Make the signed-in header fit on one row at 1280 px (e.g. a wider column or smaller gaps; fix the width comment to the real
numbers) and keep home, brand and profile on one row at 390 px (e.g. a compact `<ef-home>` at phone width). Bump the stylesheet's
`?v=` in both pages. Don't change how `/` and `/games/` look.
**Validate:** `scripts/validate.sh` passes. Task 1's check passes locally (`make up`, then `http://localhost:8080`) on all four pages
at both widths.
**Status:** ❌

### Task 3: tracking
**Runs:** unattended
**Files:** agents/ROADMAP.md (modify)
**What:** Set row E1's status to ✅ with the PR number.
**Validate:** `scripts/validate.sh` passes.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes; CI is green.

## Human test steps (preprod)
1. `node scripts/check-header-layout.mjs https://preprod.engineerfamily.net --netrc "$PREPROD_NETRC"` → every line passes.
2. `https://preprod.engineerfamily.net/strelitzia/` at 1280 px, signed out: the home link, brand, nav and "Sign in" are on one row.
3. `https://preprod.engineerfamily.net/` at 390 px, signed out: the page reads as before (no change on the home page).

## Decisions
1. Task 1's check fakes `/auth/me`, so the validator can test the signed-in layout without the dev test account's session (AM3).
