# Plan: Drop "Strelitzia dashboard" from the account menu (Strelitzia issue #98, item 2)
**Status:** ❌ Not started (planned with the user 2026-10-27)
**Risk:** low (one link in the shared header)
**Depends on:** —

## Goal
The account (profile) menu on every engineerfamily page, the Strelitzia dashboard included, no longer has a
"Strelitzia dashboard" item. People reach the dashboard from the Strelitzia page's "Open the dashboard" button and the
header's Strelitzia link.

## Context
- `services/shared/site-header.js:175-178`: `strelitzia` (from `me.pages`, with a fallback for an older `/auth/me`)
  decides whether the item shows; `links` also holds the admin "Users" item, which stays.
- Other ways in: `services/strelitzia/index.html:33` ("Open the dashboard"), `services/strelitzia/privacy.html:18`.
- The dashboard loads this same file from `/shared/site-header.js`, so one change covers it. No Strelitzia pin bump.
- Strelitzia's own Users nav link is removed separately (Strelitzia `dashboard-cleanup`, #98 item 1).

## Tasks
### Task 1: Remove the item
**Runs:** unattended
**Files:** services/shared/site-header.js (modify); the header's tests if any (grep `site-header` under `services/`)
**What:** Delete the `strelitzia` constant and its item; `links` keeps only the Users item. Leave `me.pages` in
`/auth/me` (the gate and other pages use it). Update any comment that mentions the dashboard link.
**Validate:** the repo's validate script passes; `grep -n "Strelitzia dashboard" services/shared/site-header.js` → none.
**Status:** ❌

## Human test steps (preprod)
1. Signed in, any page: the account menu shows name, email, version, Users (admins) and Sign out; no dashboard item.
2. Strelitzia page → Open the dashboard still works.

## Decisions
None open.
