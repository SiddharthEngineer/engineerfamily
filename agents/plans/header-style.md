# Plan: engineerfamily.net header in the Strelitzia page style
**Status:** 🟡 Built, PR #63 (Task 2, the preprod layout check, waits for preprod to deploy the PR)
**Risk:** review (visible on every engineerfamily.net page; needs a look on preprod)

## Goal
The header on `engineerfamily.net/` and `/games/` looks like the one on `/strelitzia/`: a flat row on the page background
with a 1 px rule under it, plain sentence-case links (not the floating, blurred pill with uppercase pill links), the same
font, sizes and Sunrise link/accent colours, light and dark. The user prefers the Strelitzia style (2026-10-19). Part 1 of a
pair: Strelitzia R46 gives the dashboard header the same look.

## Context
- `services/strelitzia/style.css:1-36`: the target. Tokens `--fg --muted --accent --link --rule` (light and dark at 1-8),
  `header` flex row with `gap: 12px 16px`, `border-bottom: 1px solid var(--rule)`, `padding-bottom: 12px`; brand 20 px/700;
  `nav a { margin-left: 16px }`; ≤800 px the nav takes its own row and scrolls; `font: 17px/1.6 system-ui, …`.
- `services/app/vite/src/styles.css:35-115`: today's header (`.site-header`, `.site-nav` pill, `.nav-menu`, `.nav-link`
  uppercase with `--accent-soft` hover, ≤600 px wrap). Lines 1-33 are the page tokens and gradient background: leave the page
  body as it is, only the header changes.
- `services/app/vite/src/App.jsx:1-31`: `Navbar` (`<ef-home>`, `ul.nav-menu` with Games and Strelitzia, `<ef-profile>`).
  The Vite site has no brand of its own beside `<ef-home>`; keep it that way.
- `services/shared/README.md`: `<ef-home>`/`<ef-profile>` are never restyled, only placed: `<ef-home>` first, `<ef-profile>`
  last on the top row at every width.
- `scripts/check-header-layout.mjs`: checks `/`, `/games/`, `/strelitzia/`, `/strelitzia/privacy` at 1280 and 390 px; it must
  still pass. Needs Playwright (`npx playwright install chromium` once).
- The page's dist is built in the Docker image (`services/app/Dockerfile`), not committed.

## Tasks
### Task 1: restyle the site header
**Runs:** unattended
**Files:** services/app/vite/src/styles.css (modify), services/app/vite/src/App.jsx (modify)
**What:** Replace the pill with the Strelitzia header: header inside the same max-width column as the page content
(`.page-shell`, 1120 px), flex row, `gap: 12px 16px`, rule under it, no background, blur, shadow or radius, not sticky.
Links: sentence case, 17 px system-ui, `color: var(--link)`; the active page (`is-active`) in `var(--fg)` with weight 600
and no pill. Add header-only tokens (`--hdr-link`, `--hdr-rule`, …) copied from the Strelitzia values, with the dark set under
`prefers-color-scheme: dark`, so the page body's palette is untouched. ≤800 px: the nav moves to its own row and scrolls,
as on the Strelitzia page. In `App.jsx` only class names may change (and the `ul` may become a plain `nav` of links); keep
`<ef-home>` first and `<ef-profile>` last.
**Validate:** `cd services/app/vite && npm ci && npm run build` → succeeds. `scripts/validate.sh` passes.
**Status:** ✅ 2026-10-21 (this commit)

### Task 2: layout check on preprod
**Runs:** unattended (after the runner deploys the PR head to preprod) — skip and flag it if preprod isn't on this PR yet
**Files:** none
**What:** `node scripts/check-header-layout.mjs https://preprod.engineerfamily.net` (add `--netrc "$PREPROD_NETRC"` only
if preprod still has basic auth).
**Validate:** every line `ok`, exit 0.
**Status:** ⏭️ skipped 2026-10-21: preprod was not on this PR during the build; flagged in PR #63

### Task 3: tracking
**Runs:** unattended
**Files:** agents/ROADMAP.md (modify), agents/plans/header-style.md (modify)
**What:** Task statuses; E3's ROADMAP status to `✅ (#<pr>)`.
**Validate:** `scripts/validate.sh` passes.
**Status:** ✅ 2026-10-21 (this commit)

## Validation
- `scripts/validate.sh` passes; CI is green; the Vite build succeeds.
- `node scripts/check-header-layout.mjs https://preprod.engineerfamily.net` → all `ok`.

## Human test steps (preprod)
1. Open `https://preprod.engineerfamily.net/` and `/strelitzia/` in two tabs at desktop width and flip between them: same
   header height, rule, link font and colours; only the Strelitzia brand differs.
2. Same in dark mode (OS setting).
3. At phone width (390 px): `<ef-home>` and Sign in / profile on the top row, Games and Strelitzia on a row below.
4. Signed in as the dev test account: the profile menu still opens and Sign out works.

## Decisions
1. The Strelitzia page's header is the house style (user, 2026-10-19); the engineerfamily page body keeps its own look.
2. Header-only tokens, so the page palette doesn't shift as a side effect.
3. Not sticky, like the Strelitzia page.
4. No dark header colours (build, 2026-10-21): the page body has no dark mode, so Strelitzia's dark link colours would be
   unreadable on it. The header keeps its light values until the page gets a dark palette.
