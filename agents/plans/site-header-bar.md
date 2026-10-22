# Plan: one site header bar, like the Strelitzia dashboard's top bar
**Status:** ❌ Not started
**Risk:** review (visible on every engineerfamily.net page; changes `scripts/` and `agents/settings/`)
**Depends on:** - (replaces header-style, PR #63, closed 2026-10-22)

## Goal
Every engineerfamily.net page except the Strelitzia dashboard shows the same header: a solid, full-width bar at the very
top of the page that looks like the dashboard's top bar (`/strelitzia/dashboard/`). It is not floating and not sticky:
it scrolls away with the page. That covers `/`, `/games/`, `/privacy`, `/strelitzia/` and `/strelitzia/privacy`. In the bar:
a **home icon** (replaces the "• engineerfamily" pill), the site links **Games** and **Strelitzia**, and the profile
avatar last. **Sign out** and **Users** move into the avatar's dropdown, with no separate Sign out button. The header is
always light, even in OS dark mode. The dashboard keeps its own bar and links (Strelitzia R46); it only picks up the new
home icon and dropdown, because those are the shared `<ef-home>` / `<ef-profile>`.

## Context
- The target look, Strelitzia `dashboard/src/styles.css:63-64,213-216` (light tokens at 3-29): `.topbar` is a flex row,
  `gap: 16px; padding: 8px 16px; background: var(--surface) /* #ffffff */; border-bottom: 1px solid var(--border) /* #e4d8c6 */`,
  full width, not sticky. Nav links: `padding: 4px 10px; border-radius: 999px; color: var(--muted) /* #6b5e52 */`, no
  underline; hover `#2a1f17`; active `background: #f5ede0; color: #2a1f17; font-weight: 600`. Font `14px/1.45 system-ui,
  -apple-system, 'Segoe UI', Roboto, sans-serif`. Measure its height on preprod before you start (expect about 53 px).
- `services/shared/site-header.js` (205 lines): `<ef-home>` (pill with dot + wordmark, `compact` hides the wordmark) and
  `<ef-profile>` (initials button + menu with name, email, "Strelitzia dashboard"; then a separate `.signout` pill). Shadow
  DOM; colours go dark under `prefers-color-scheme: dark`. `services/shared/README.md` is the contract.
- Pages that build a header by hand today: `services/app/vite/src/App.jsx:3-31` + `styles.css:35-115` (floating sticky pill),
  `services/app/vite/public/privacy.html:18-32`, `services/strelitzia/index.html:15-20` and `privacy.html:15-20` with
  `services/strelitzia/style.css:17-37` (header inside `main`, Strelitzia brand + Dashboard/Privacy/GitHub nav). `index.html`
  loads `style.css?v=3`: bump it. `.home-shell`/games pages use `min-height: calc(100vh - 90px)` for the old header.
- Strelitzia owner check for the Users link: `GET /strelitzia/dashboard/api/auth/me` →
  `{enabled, user: {role: "owner" | …}, …}` (same origin, cookie). The Users page is `/strelitzia/dashboard/users` (200 on
  preprod). On preprod the dev test account is the Strelitzia owner. site-perms-2 (E9) later swaps this for `me.admin`.
- `scripts/check-header-layout.mjs` (119 lines): Playwright, fakes `/auth/me`, checks `/`, `/games/`, `/strelitzia/`,
  `/strelitzia/privacy` at 1280 and 390 px. It looks for `header nav` and a Sign out button beside the avatar; both change.
- `agents/settings/validate.json`: the validator could not run the Vite build or the layout check on PR #63 (not allowed).

## Tasks
### Task 1: shared pieces: home icon, dropdown, `<ef-site-header>`
**Runs:** unattended
**Files:** services/shared/site-header.js (modify), services/shared/README.md (modify)
**What:**
- `<ef-home>`: a 36×36 round button with an inline SVG house icon (stroke `currentColor`, ~18 px), `aria-label` and
  `title` "engineerfamily home", link to `/`. No wordmark, no dot. `compact` stays accepted and does nothing.
- `<ef-profile>`: drop the separate Sign out pill. The menu lists name, email, a rule, "Strelitzia dashboard", "Users"
  (only when `/strelitzia/dashboard/api/auth/me` answers `enabled` and `user.role === "owner"`; fetch it once per page, only
  when signed in; any error → no link; add the link when it answers, don't block the menu), a rule, then a **Sign out**
  menu item (a `<button>` styled like the links, same `POST /auth/logout` + reload). Keyboard: Escape, focus-out and
  first-item focus keep working.
- A `light` attribute on both: when present, the dark-mode token block doesn't apply (`:host(:not([light]))` inside the media query).
- New `<ef-site-header active="games|strelitzia">`: light DOM (no shadow, so `header nav` stays queryable), renders
  `<header class="ef-site-header"><ef-home light></ef-home><nav aria-label="Site"><a href="/games/">Games</a><a
  href="/strelitzia/">Strelitzia</a></nav><ef-profile light></ef-profile></header>`, marks the active link with
  `aria-current="page"`, and injects one `<style>` into `<head>` with every rule scoped under `ef-site-header` and the
  dashboard values above hard-coded (always light, `color-scheme: light`), `display: block`, full width, profile pushed right.
  At 390 px everything stays on one row with no sideways scroll.
- README: document the three elements and that pages other than the dashboard use `<ef-site-header>` as the first child
  of `<body>` and add no header CSS of their own.
**Validate:** `node --check services/shared/site-header.js` → no output; `scripts/validate.sh` passes.
**Status:** ✅ 2026-10-22

### Task 2: every page uses `<ef-site-header>`
**Runs:** unattended
**Files:** services/app/vite/src/App.jsx (modify), services/app/vite/src/styles.css (modify), services/app/vite/public/privacy.html (modify), services/strelitzia/index.html (modify), services/strelitzia/privacy.html (modify), services/strelitzia/style.css (modify)
**What:** Replace each hand-built header with `<ef-site-header>` at the very top of the page (y = 0, not inside a padded
`main`): `active="games"` on `/games/`, `active="strelitzia"` on both Strelitzia pages, none on `/` and `/privacy`. In the
Vite app, `Navbar` renders `<ef-site-header active={…}>` from the route (React: use `class`, not `className`, and set
`active` as an attribute) and the old `.site-header`/`.site-nav`/`.nav-*` CSS goes; fix the old `100vh - 90px` min-heights.
On the Strelitzia pages, the brand and the Dashboard · Privacy · GitHub links move into the page body as a small row
above the `h1` (page style, not header style); remove the page's `header` rules and `nav a` margin rule; bump `style.css?v=`.
Page bodies are otherwise unchanged.
**Validate:** `cd services/app/vite && npm ci && npm run build` → builds; `scripts/validate.sh` passes.
**Status:** ✅ 2026-10-22

### Task 3: layout check and validator permissions
**Runs:** unattended
**Files:** scripts/check-header-layout.mjs (modify), agents/settings/validate.json (modify)
**What:** Script: pages `/`, `/games/`, `/privacy`, `/strelitzia/`, `/strelitzia/privacy`; also fake
`/strelitzia/dashboard/api/auth/me` as `{enabled: true, user: {role: "owner"}}`. Per page and width check:
`ef-site-header` top is 0 and its width equals the viewport; its height is the same on every page (±1 px); `ef-home` and
`ef-profile` share a top (±4 px); no sideways scroll; the avatar ends inside the viewport; clicking the avatar shows a menu
with "Users" and "Sign out" and there is no other Sign out on the page. Keep the output format (one line per page/width,
exit codes). validate.json: allow `Bash(npm ci --prefix services/app/vite:*)`, `Bash(npm run build --prefix services/app/vite:*)`,
`Bash(node --check:*)`, `Bash(node scripts/check-header-layout.mjs:*)` and `Bash(npx playwright install chromium)`.
**Validate:** `node --check scripts/check-header-layout.mjs`; `python3 -m json.tool agents/settings/validate.json >/dev/null`;
`scripts/validate.sh` passes. (The script runs against preprod in the Human test steps, after the runner deploys the PR.)
**Status:** ❌

### Task 4: tracking
**Runs:** unattended
**Files:** agents/ROADMAP.md (modify), agents/plans/site-header-bar.md (modify)
**What:** Task statuses; E3's status to `✅ (#<pr>)`.
**Validate:** `scripts/validate.sh` passes.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes; CI is green; the Vite build succeeds.

## Human test steps (preprod)
1. `node scripts/check-header-layout.mjs https://preprod.engineerfamily.net` → every line `ok`, exit 0.
2. At 1280 px, signed in as the dev test account, open `/`, `/games/`, `/privacy`, `/strelitzia/`, `/strelitzia/privacy`
   and `/strelitzia/dashboard/`. Each starts with a solid white full-width bar at y = 0 with a 1 px rule under it; the first
   five have the same height as the dashboard's bar (±1 px). Home icon first, avatar last; Games and Strelitzia links in
   the dashboard's link style, the current one highlighted.
3. On `/strelitzia/`, scroll down 400 px: the header has scrolled out of view (not sticky, not floating).
4. With dark mode emulated, `/` and `/strelitzia/` still show the light header.
5. Open the avatar menu on `/`: name, email, Strelitzia dashboard, Users, Sign out; no Sign out button outside the menu.
   Users opens `/strelitzia/dashboard/users`. On the dashboard the same menu appears, and the home icon goes to `/`.
6. At 390 px on `/` and `/strelitzia/`: one header row, nothing cut off, no sideways scroll.
7. Last: Sign out from the menu → the header shows Sign in.

## Decisions
1. 2026-10-22 (user): the dashboard's top bar is the house style, not the static `/strelitzia/` page's header
   (supersedes the 2026-10-19 decision and PR #63). Solid bar that scrolls away; the dashboard keeps its own links.
2. 2026-10-22 (user): always light for now; dark mode for engineerfamily pages is a backlog item.
3. 2026-10-22 (user): Users shows for the Strelitzia owner until site-perms (E9) adds the site `admin` flag.
4. The Strelitzia brand and its page links move into the page body so the header is identical on every non-dashboard page.
