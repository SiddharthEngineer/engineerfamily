# Plan: Site permissions 2/4: Users page and profile menu link
**Status:** ❌ Not started
**Risk:** review (new admin UI and a change to the shared site header)
**Depends on:** site-perms-1-store; header-style (E3, edits the same `site-header.js`)

## Goal
Admins get a **Users** page at `https://engineerfamily.net/users/`, linked from the profile dropdown (only admins see the
link). It shows one table: a row per user plus a "Everyone (signed out or not invited)" row, and columns Admin, Site,
Strelitzia, Cap Spend, Bracket Analyzer (driven by the API's `pages` list, so future pages appear without UI changes).
Admins can invite an email, tick or untick each page, set the Strelitzia cap and remove users. For an admin row every other
checkbox shows checked and disabled. Nobody else can see the page or its data.

## Context
- `services/app/vite/src/App.jsx:1-85`: routes and the page-card layout to mirror (`page-shell`, `home-card`).
- `services/app/vite/src/styles.css`: site tokens; reuse them, no new colours.
- `services/app/app.py:30-55`: `/games/` serves the SPA; add `/users/` the same way.
- `services/shared/site-header.js:140-200`: the `<ef-profile>` menu built from `/auth/me`. It currently always lists
  "Strelitzia dashboard".
- API from part 1 (`services/app/admin.py`): `GET/POST /api/admin/users`, `PATCH /api/admin/users/<email>`,
  `PATCH /api/admin/everyone`, `DELETE /api/admin/users/<email>`; `/auth/me` has `admin` and `pages`.
  Read `admin.py` for the exact shapes before writing the client.
- Strelitzia's Users page is the UX reference (read only): `../Strelitzia/dashboard/src` (search for `admin/users`).
- Gotcha: `dist/` is gitignored and built in the Dockerfile; don't commit a build.

## Tasks
### Task 1: Users page
**Runs:** unattended
**Files:** services/app/vite/src/UsersPage.jsx (new), services/app/vite/src/App.jsx (modify), services/app/vite/src/styles.css (modify), services/app/app.py (modify)
**What:**
- Route `/users/` in Flask (serves the SPA) and in React. On load the page calls `/auth/me`; not an admin → "You don't
  have access to this page" (signed out: a Sign in link with `next=/users/`). The server API enforces this too.
- Invite form: one email field + "Invite" button → `POST`; errors (409, 400) shown inline.
- Table: columns `Email | Admin | <one per page, in API order; a cap page is followed by "Cap Spend">` + a Remove button.
  - Checkbox change → `PATCH` right away (optimistic, revert and show the error on failure). Cap: a `$` number input saved
    on blur/Enter; blank = no cap (shown as "No cap").
  - Admin row: every page checkbox checked + disabled, cap shows "No cap" disabled.
  - Everyone row (pinned first, labelled "Everyone (signed out or not invited)"): no Admin, no Remove; `needs_account`
    pages and Cap disabled with a tooltip "Needs a signed-in, invited user".
  - Your own row: Admin and Remove disabled (you can't demote or remove yourself; the API also guards the last admin).
- `db: false` from the API → a banner "No database configured: read-only" and all inputs disabled.
- Accessible: real `<table>`, `<th scope>`, labelled checkboxes (`aria-label="Strelitzia for a@b.c"`). Fits a phone by
  scrolling the table horizontally inside its card.
**Validate:** `cd services/app/vite && npm ci && npm run build` → builds; `cd services/app && python -m pytest -q` → passes
(add a test that `GET /users/` returns the SPA).
**Status:** ❌

### Task 2: Profile menu link
**Runs:** unattended
**Files:** services/shared/site-header.js (modify)
**What:** In the signed-in menu, show "Users" (`/users/`) only when `me.admin`, and "Strelitzia dashboard" only when
`me.pages` includes `strelitzia` (when `pages` is missing, as on an older app, keep today's always-shown link). Keep the
menu's focus handling working when the first link changes. Don't restyle (E3 owns the look).
**Validate:** `scripts/validate.sh` → passes; `node --check services/shared/site-header.js` → no output.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes; `npm run build` passes; `python -m pytest -q` passes.
- Preprod: `curl -s -o /dev/null -w "%{http_code}" https://preprod.engineerfamily.net/users/` → 200 (the SPA; data is API-gated).

## Human test steps (preprod)
1. Signed in as yourself on `https://preprod.engineerfamily.net/`, open the profile menu: "Users" is listed. Click it.
2. The table shows you and the test account as admins (all boxes checked and greyed) and the Everyone row with nothing ticked.
3. Invite a throwaway address, tick Strelitzia, set Cap Spend to 3, reload: the values stuck. Remove it.
4. Sign in as the test account in its browser profile and untick its own Admin: the box is disabled.

## Decisions
1. The page lives in the existing Vite app (no new service); the API from part 1 is the only data path.
2. Changes save per click (no Save button), like Strelitzia's Users page.
3. Columns come from the API's `pages`, so a new restricted page needs no UI work.
