# Plan: the Strelitzia homepage becomes a scrollable demo
**Status:** ❌ Not started
**Risk:** review (the public Strelitzia homepage; Google's OAuth reviewers read the Drive section)

## Goal
`engineerfamily.net/strelitzia/` shows what Strelitzia does instead of describing it. The public can't open the dashboard
(invite only), so the page acts the flow out with made-up sample data, in static HTML/CSS/JS: add a job by link → the
posting is read → a fit score with reasons → a tailored resume and cover letter → tracking the application. One long page,
each section a "screen" in the dashboard's Sunrise look, revealed as you scroll (references: onepagelove.com/tag/demo).
Invited users get an "Open the dashboard" link; everyone else "Run it yourself" (GitHub).

## Context
- `services/strelitzia/index.html` (47 lines): today's page. Keep the `<ef-site-header>` (E3), the brand row above the
  `h1` and the footer exactly as they are; line numbers moved in E3, so find the sections by reading the file.
- `services/strelitzia/style.css` (45 lines): Sunrise tokens and page CSS (the header has none since E3). `index.html:10` loads it as `style.css?v=3`:
  bump `?v=` on every change (Cloudflare may cache for 4 h, see the comment there).
- nginx serves the folder at `/strelitzia/` with `try_files $uri $uri.html $uri/` and `Cache-Control: no-cache`
  (`services/nginx/nginx.{preprod,prod}.conf`), so new files (`demo.js`, `demo.css`) need no nginx change. No build step.
- Keep the Drive paragraph (`index.html:33-37`) word for word: it states the `drive.file` scope for Google's reviewers. Keep
  the license/GitHub paragraph and the privacy link.
- The dashboard's look to imitate is Strelitzia `dashboard/src/styles.css` (job rows, score badge, status chips): copy the
  look in a few lines of CSS, don't import it.
- `scripts/check-header-layout.mjs` covers `/strelitzia/` at 1280 and 390 px and must still pass.

## Tasks
### Task 1: demo sections with sample data
**Runs:** unattended
**Files:** services/strelitzia/index.html (modify), services/strelitzia/demo.css (new), services/strelitzia/style.css (modify, only if shared tokens are needed)
**What:** Hero (headline, one-line lede, two buttons: "Open the dashboard" → `/strelitzia/dashboard/`, "Run it yourself" →
GitHub). Then five sections, each a short heading + one sentence + a mock screen in plain HTML: (1) a link pasted into an
"Add job" box; (2) the extracted posting card (title, company, location, salary); (3) the fit score (e.g. 82) with three
reasons and one gap; (4) a resume excerpt with tailored lines highlighted next to the original, plus "cover letter.pdf"
and "resume.pdf" chips; (5) a jobs list with status chips (Applied, Interview, Offer). Then "Your data stays yours"
(self-hosted, the Drive paragraph verbatim), then "Get it" (license, GitHub). Sample data: invented companies and roles
(e.g. "Northwind Robotics, Senior Backend Engineer"), no real people or employers. Mock screens are `aria-hidden` art with a
text sentence beside them, so the page reads fine without them. Works at 390 px with no sideways scroll.
**Validate:** `scripts/validate.sh` passes. `grep -c 'drive.file' services/strelitzia/index.html` → `1`.
**Status:** ❌

### Task 2: scroll reveal and small motion
**Runs:** unattended
**Files:** services/strelitzia/demo.js (new), services/strelitzia/index.html (modify: one `<script defer>`)
**What:** An `IntersectionObserver` adds `.is-visible` to each section as it enters (fade/slide in), types the link into
the Add-job box once, counts the score up to its value, and highlights the tailored lines. No library, under ~80 lines.
With `prefers-reduced-motion: reduce` or without JS, everything shows in its final state at once (the default CSS is the
final state; motion is opt-in from JS).
**Validate:** `node --check services/strelitzia/demo.js` → no output. `scripts/validate.sh` passes.
**Status:** ❌

### Task 3: checks on preprod
**Runs:** unattended (after the runner deploys the PR head) — skip and flag it if preprod isn't on this PR yet
**Files:** none
**What:** `node scripts/check-header-layout.mjs https://preprod.engineerfamily.net`, and
`curl -s -o /dev/null -w '%{http_code}' https://preprod.engineerfamily.net/strelitzia/demo.js` → `200`.
**Validate:** both pass.
**Status:** ❌

### Task 4: tracking
**Runs:** unattended
**Files:** agents/ROADMAP.md (modify), agents/plans/strelitzia-demo.md (modify)
**What:** Task statuses; E4's ROADMAP status to `✅ (#<pr>)`.
**Validate:** `scripts/validate.sh` passes.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes; CI is green.
- The header layout check passes on preprod; `demo.js` and `demo.css` answer 200.

## Human test steps (preprod)
1. Open `https://preprod.engineerfamily.net/strelitzia/` signed out at desktop width and scroll: each section animates in
   once, the score counts up, the page reads as a walk through the product.
2. Same at 390 px: no sideways scroll, mock screens fit.
3. With "reduce motion" on in the OS: everything is visible at once, no animation.
4. "Open the dashboard" opens the sign-in card when signed out; "Run it yourself" opens the GitHub repo.
5. The Drive paragraph and the privacy link are still there.

## Decisions
1. A static mock with made-up data, not screenshots (they go stale) or a public demo dashboard (new auth mode, DB and abuse
   limits) (user, 2026-10-19).
2. The Drive text stays verbatim because Google's OAuth review reads it.
3. Motion is progressive: no JS or reduced motion shows the final state.
