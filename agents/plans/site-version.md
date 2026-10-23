# Plan: the site header shows what's deployed, and prod deploys promote the GitHub release
**Status:** ✅ Done 2026-10-23, except `agents/runner.toml` `[release]` and the settings deny entries (Left for you)
**Risk:** review (every page's header; `Makefile`, `scripts/`, `agents/runner.toml`)
**Depends on:** E3 [site-header-bar](site-header-bar.md) (same header file; queue order), agent-runner A21
[runner-15-versions](https://github.com/SiddharthEngineer/agent-runner/blob/main/agents/plans/runner-15-versions.md)
(`[release]` and `agent-runner versions`)

## Goal
The header and GitHub Releases tell the user what's on prod and preprod (user, 2026-10-22). Muted small text at the top
right of every page, just left of the avatar, linking to GitHub:
- **prod:** `v1.4` → the `v1.4` release (`…/releases/tag/<its tag>`).
- **preprod on main:** the exact tag, `v1.4.2` → that tag's release page; `v1.4.2+3` if main has 3 untagged
  commits past it (plan or doc commits, not PRs).
- **preprod on a PR branch:** the branch name, `agent/site-version` → `…/pulls?q=is:pr+head:agent/site-version`.
It lives in `<ef-profile>`, so the Strelitzia dashboard (which uses the shared `<ef-profile>`) shows it too, with no
Strelitzia change. Prod deploys become one command that deploys the newest tag and promotes its release (A21's `promote`);
the old tag flow goes.

## Context
- `services/shared/site-header.js` after E3: `<ef-profile>` (shadow DOM, one `/auth/me` per page, line ≈78); its README is
  the contract. `/shared/` is served from `./services/shared` (bind mount, no-cache) by every compose file.
- `Makefile:158-167` `preprod-deploy` (`git checkout -B preprod $(ref)` in `/srv/engineerfamily-preprod`, then compose).
  The runner deploys a PR with `ref=<head sha>`; the branch `agent/<slug>` is fetched there too. `Makefile:203-270`: the
  old release targets (`tag-preprod`, `tag-prod`, `deploy-preprod`, `validate-release-tagging`, `sync-release-branch`,
  `delete-tag`) and `scripts/release_branch_sync.sh`. `deploy-prod` (`gh workflow run deploy.yml … ref=`) stays.
- Prod's checkout is moved by `scripts/vps/engineerfamily-deploy` (root-owned copy in `/usr/local/sbin`, `g()` runs git as
  `deploy`); a change there goes live only when the user reinstalls it (M3). `.github/*` can't be pushed by the agents'
  token: leave `deploy.yml` alone.
- `scripts/prod-changes.sh`: "newest prod tag" by version sort; switch it to the newest full release's tag
  (`gh release list --exclude-pre-releases --limit 1`), falling back to version sort without gh.

## Tasks
### Task 1: `version.json` on every deploy
**Runs:** unattended
**Files:** scripts/site-version.sh (create), Makefile (modify), scripts/vps/engineerfamily-deploy (modify), .gitignore (modify)
**What:** `scripts/site-version.sh <prod|preprod> [dir]` writes `services/shared/version.json` (`{"label", "url"}`, mode
644, gitignored) from the checkout's HEAD: prod: exact `vX.Y.Z` tag → `vX.Y` (no tag: short sha); preprod: exact tag →
it; else a remote branch at HEAD other than main/preprod/prod → its name; else nearest tag on main → `vX.Y.Z+N`; else
short sha. `preprod-deploy` and the root deploy script call it after checkout (the root script as `deploy`, via `g`).
**Validate:** `scripts/validate.sh` passes; `bash scripts/site-version.sh preprod .` in a temp clone at a tag, past a tag
and on a branch prints the three expected labels (note them in the PR).
**Status:** ✅ 2026-10-23 (b3537c5)

### Task 2: the header shows it
**Runs:** unattended
**Files:** services/shared/site-header.js (modify)
**What:** `<ef-profile>` fetches `/shared/version.json` once per page (`cache: 'no-store'`) and renders
`Version <label>` as its own section of the avatar menu, between the name/email and the Strelitzia dashboard link (with
the menu's rules around it): muted 13px, links to `url`, `title="Deployed version"`. Signed out there is no menu, so no
version. Missing or bad file → nothing shown, no console error. The header row itself doesn't change
(`scripts/check-header-layout.mjs` must still pass unchanged). Document the
element in Task 4's DEPLOY.md section (the shared README stays as is, to keep this plan in budget).
**Validate:** `scripts/validate.sh` passes; `node --check services/shared/site-header.js`.
**Status:** ✅ 2026-10-23 (f373142)

### Task 3: one prod command; retire the old tag flow; turn on `[release]`
**Runs:** unattended
**Files:** Makefile (modify), scripts/release_branch_sync.sh (delete), scripts/prod-changes.sh (modify), agents/runner.toml (modify)
**What:** New `make prod-release [v=X.Y.Z]` (the user's; agents never run it): `agent-runner versions sync engineerfamily`,
pick `v` or the newest tag, show `make prod-changes`, ask `Deploy <tag> to prod? [y/N]`, `deploy-prod ref=<tag>`, wait
for the run (`gh run watch` on the newest deploy.yml run), then `agent-runner versions promote engineerfamily <tag>`.
A failed deploy promotes nothing. Remove the old release targets and the script; keep `deploy-prod` for rollbacks
(`make deploy-prod ref=<older tag>`, no promote). `prod-changes.sh` as in Context. `runner.toml`: `[release]` with `tags = true`.
**Validate:** `scripts/validate.sh` passes; `make -n prod-release` prints the steps.
**Status:** ✅ 2026-10-23 except `runner.toml` (the agent's permission check refused that edit and the deny-list
addition, so both are in Left for you); `make -n prod-release` is blocked for agents, so the recipe was read, not run.

### Task 4: docs and tracking
**Runs:** unattended
**Files:** agents/DEPLOY.md (modify), AGENTS.md (modify), agents/ROADMAP.md (modify), agents/plans/site-version.md (modify)
**What:** DEPLOY.md: replace the release-branch model with: every PR merge → patch tag + the `vX.Y` pre-release (runner);
`make prod-release` → deploy + full release; the next merge starts `vX.(Y+1).0`; what the header shows where; rollback.
Old `-preprod` tags and `release-v*` branches stay as history. AGENTS.md: the Deploys bullet becomes `make prod-release` (rollback `make deploy-prod ref=<tag>`), the Map drops release-branch sync, and the prod rule names `prod-release`. ROADMAP: E11 row, M3 and AM9 steps.
**Validate:** `scripts/validate.sh` passes.
**Status:** ✅ 2026-10-23

## Validation
- `scripts/validate.sh` passes; CI is green.

## Human test steps (preprod)
1. `curl -sS https://preprod.engineerfamily.net/shared/version.json` → `label` is this PR's branch name and `url`
   is `https://github.com/SiddharthEngineer/engineerfamily/pulls?q=is:pr+head:<branch>`.
2. At 1280 px on `/`, `/games/`, `/strelitzia/` and `/strelitzia/dashboard/` (signed in as the dev test account): click
   the avatar; `Version <branch>` is its own section between the name/email and Strelitzia dashboard; it opens the PR
   search above.
3. At 390 px on `/` and `/strelitzia/dashboard/`: the menu fits on screen, a long branch name wraps, no sideways scroll.
4. `node scripts/check-header-layout.mjs https://preprod.engineerfamily.net` → every line `ok`, exit 0.
5. Signed out, `/` shows only Sign in (no version text).

## Left for you
- Add `[release]` / `tags = true` to `agents/runner.toml` (before the `[preprod]` table) and deny `make prod-release`
  and `agent-runner versions promote` in `.claude/settings.json`: the agent's permission check refused both edits.
- M3: reinstall `scripts/vps/engineerfamily-deploy` as root (`scripts/vps/README.md`); until then prod's header shows nothing.
- AM9 (once, after A21 is installed and this merges): `agent-runner versions promote engineerfamily v1.3.3` (prod runs it).
  The next runner tick then tags main `v1.4.0` and opens the `v1.4` pre-release.

## Decisions
1. 2026-10-22 (user): prod shows `vX.Y`, preprod `vX.Y.Z` or the PR's branch; text links to the release; dashboard too.
2. 2026-10-22 (user): retire `tag-preprod`/`tag-prod`/release branches; prod deploy = newest tag + promote. Start at v1.4.
3. `+N` for untagged commits on main past a tag, so preprod never claims a tag it isn't exactly on.
