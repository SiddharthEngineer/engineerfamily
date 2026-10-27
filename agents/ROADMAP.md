# engineerfamily Roadmap

The single tracker for planned work. Each row links to a plan in `agents/plans/`. Finished plans move to `agents/plans/done/`,
and their history is in git and PRs. Workflow: see the PIV loop in `AGENTS.md`.

Status: ⏳ queued · 🔄 in progress · 🟡 code done, user steps pending · ⏸ blocked · ✅ done (then archived)

## Active

The earlier engineerfamily Parts of the shared-runner programme (ef-validate-ci, ef-agents-layout, ef-runner-config) are tracked
in agent-runner's [ROADMAP](https://github.com/SiddharthEngineer/agent-runner/blob/main/agents/ROADMAP.md) (A5, A12, A13).
New engineerfamily plans go here. E1 ([header-fit](plans/done/header-fit.md), #54) is on prod since v1.3.3 (2026-10-19) and archived.

| ID | Initiative | Plan | Risk | Status | Depends on |
|---|---|---|---|---|---|
| E2 | Preprod without basic auth (Google sign-in only, `noindex`); unblocks agent-runner AM3 | [preprod-open](plans/preprod-open.md) | review | ✅ (#58) | - |
| E3 | One site header bar like the Strelitzia dashboard's top bar: home icon, Games/Strelitzia links, Users + Sign out in the profile menu (replaces header-style, #63 closed) | [site-header-bar](plans/site-header-bar.md) | review | ✅ (#66) | - |
| E4 | Strelitzia homepage as a scrollable demo with made-up data | [strelitzia-demo](plans/strelitzia-demo.md) | review | ✅ (#70), preprod checks (Task 3) pending | Strelitzia R46 (queue order) |
| E5 | Wordle solver 1/3: vectorized solver core, tests, CI (Wordle repo, cross-repo PR) | [wordle-solver-1-core](plans/wordle-solver-1-core.md) | low | ✅ 2026-10-22: Wordle PR #1 (solver, tests, CI `test` green); waiting to be merged | M1 |
| E6 | Wordle solver 2/3: tile-grid page, FastAPI, Docker image (Wordle repo, cross-repo PR) | [wordle-solver-2-web](plans/wordle-solver-2-web.md) | low | ✅ 2026-10-22: Wordle PR #2 (page, API, Docker image), stacked on #1; waiting to be merged after #1 | E5 |
| E7 | Wordle solver 3/3: `wordle` service, nginx `/wordle/`, make targets, home link | [wordle-solver-3-deploy](plans/wordle-solver-3-deploy.md) | review | 🟡 Tasks 1–3 done 2026-10-22, PR open; Task 4 (/srv checkouts + preprod) left for the user | E6, M1 |
| E8 | Site permissions 1/4: `engineerfamily` DB, per-page grants, admin API, `/auth/verify?page=` | [site-perms-1-store](plans/site-perms-1-store.md) | review | ✅ built 2026-10-23, PR open (preprod checks after M2) | E4 (queue order) |
| E9 | Site permissions 2/4: admin-only Users page at `/users/`, profile-menu link | [site-perms-2-users-page](plans/site-perms-2-users-page.md) | review | ✅ built 2026-10-23 (PR pending review) | E8, E3 |
| E10 | Site permissions 3/4: nginx enforces Site + per-page access, no-access pages | [site-perms-3-gate](plans/site-perms-3-gate.md) | review | ✅ built 2026-10-24, PR open (preprod checks after M2) | E9, M2 (preprod half) |
| E11 | Version in the header's account menu (prod `vX.Y`, preprod `vX.Y.Z` or the PR branch, dashboard too); `make prod-release` deploys the newest tag and promotes its release; old tag flow retired | [site-version](plans/site-version.md) | review | ✅ (#74) | E3, agent-runner A21 |
| E12 | Pins 1/2: `components.toml` pins Strelitzia and Wordle to tags; every engineerfamily deploy (prod and preprod) checks the pins out before it builds | [components-1-pins](plans/components-1-pins.md) | review | ✅ (#80); prod needs M5 | M4, E11 |
| E13 | Pins 2/2: `make prod-release` ships one engineerfamily tag with its pins (one preview, one y/N, health checks), then promotes every release it moved | [components-2-release](plans/components-2-release.md) | review | ✅ (PR in review); first real run after M5 | E12, M5 before the first real run |
| E14 | Account menu: drop the "Strelitzia dashboard" item (Strelitzia #98) | [header-no-dashboard-link](plans/header-no-dashboard-link.md) | low | ⏳ | - |

## Backlog
- Dark mode for the engineerfamily pages and the site header (user, 2026-10-22: "future change"). Today the header is always light.

## Manual steps (you)

| ID | Step | Done |
|---|---|---|
| M1 | Give the VPS runner's token push access to SiddharthEngineer/Wordle and enable "Allow auto-merge" there (before E5). Create `/srv/Wordle-prod`, `/srv/Wordle-preprod` (deploy:srv) and `~/src/Wordle` before E7's first preprod or prod deploy. Done 2026-10-21: token push checked (test branch made and deleted), auto-merge on (user); `/srv/Wordle-{prod,preprod}` (deploy:srv, 2775, `core.sharedRepository=group`, in `safe.directory`) and `~/src/Wordle` cloned over HTTPS at `main` | ☑ |
| M2 | Site permissions DB and seed list (after E8 merges, before E10 runs). Preprod: in `/srv/engineerfamily-preprod/.env` add `SITE_DB_PASSWORD_PREPROD=` (`openssl rand -hex 24`) and `SITE_ADMIN_EMAILS=` your Gmail and the dev test account's (comma-separated), then `make preprod-site-db-init` and `make preprod-deploy`. Prod, before the first prod deploy with E8-E10: `SITE_DB_PASSWORD=`, `SITE_ADMIN_EMAILS=` your Gmail, `SITE_MEMBER_EMAILS=` the dev test account, then `make site-db-init`. After prod is live, re-invite the existing Strelitzia users on `/users/`. | ☐ |
| M3 | After E11 merges: (1) add `[release]` with `tags = true` to `agents/runner.toml` and `"Bash(make prod-release:*)"`, `"Bash(agent-runner versions promote:*)"` to the deny list in `.claude/settings.json` (the agent's permission check refused both edits); (2) reinstall `scripts/vps/engineerfamily-deploy` as root (`scripts/vps/README.md`), so prod deploys write `version.json`; (3) agent-runner AM9, once: `agent-runner versions promote engineerfamily v1.3.3` (what prod runs), so the next runner tick tags main `v1.4.0` and opens the `v1.4` pre-release. From then on prod deploys are `make prod-release`. | ☐ |
| M4 | Before E12 runs: Strelitzia and Wordle get releases. (1) Strelitzia: `[release]` with `tags = true` in `agents/runner.toml`, and `"Bash(make prod-release:*)"`, `"Bash(agent-runner versions promote:*)"` in `.claude/settings.json`'s deny list (agents can't edit either). (2) Wordle: a new `agents/runner.toml` (`[repo]` name `wordle`, `SiddharthEngineer/Wordle`, base `main`, merge `merge`; `[validate]` running pytest; `[gate]` with `Dockerfile`, `.github/*`, `agents/runner.toml`, `.claude/settings.json` high-risk; `[release]` `tags = true`), the same deny entries in a new `.claude/settings.json`, and `~/.config/agent-runner/repos/wordle.env` with `AGENT_REPO=$HOME/src/Wordle`; check with `agent-runner config check`. (3) Confirm prod still runs Strelitzia `bdca7b3` and Wordle `3a0ccf2` (`git -C /srv/<Repo>-prod rev-parse --short HEAD`), tag each `v1.0.0` there (annotated, pushed), then `agent-runner versions promote strelitzia v1.0.0` and `… wordle v1.0.0`. Check: `agent-runner versions status strelitzia` / `wordle` show `v1.0` as the newest full release. E12's `components.toml` starts at these tags. Done 2026-10-26 (user): Strelitzia#97 and Wordle#4 merged, both `v1.0` full releases on `v1.0.0` (prod's commits). | ☑ |
| M5 | After E12 merges: reinstall `scripts/vps/engineerfamily-deploy` as root (`scripts/vps/README.md`), so prod deploys check out the pins (check: the next prod `deploy.yml` log shows `→ strelitzia at <tag>` and `→ wordle at <tag>`). Until then prod deploys build whatever `/srv/<Repo>-prod` holds, and E13's `prod-release` would ship pins it doesn't deploy: don't run it before this. | ☐ |

## Decisions (current)
- 2026-10-22 (user): every PR merge gets a patch tag and updates the `vX.Y` pre-release; a prod deploy promotes it and the next merge starts `vX.(Y+1)`. Header shows prod `vX.Y`, preprod `vX.Y.Z` or the PR branch, linking to GitHub. Release branches and `-preprod` tags retired; start at v1.4 (E11, agent-runner A20/A21).
- 2026-10-21 (user): engineerfamily owns site access: a Users page with per-page grants (Site, Strelitzia + cap, Bracket Analyzer, …), admins, and an Everyone row (prod: Site; preprod: nothing). Postgres DB; seed emails only in `/srv` `.env`; existing Strelitzia users re-invited by hand (E8-E10, Strelitzia R47).
- 2026-10-20 (user): the Wordle solver lives at `engineerfamily.net/wordle/`, public, as a FastAPI container built from the Wordle repo like Strelitzia; app code in Wordle, infra in engineerfamily; Wordle PRs auto-merge on green CI.
- 2026-10-22 (user): the Strelitzia **dashboard's** top bar is the house style (replaces the 2026-10-19 choice of the static page's header). Every other page gets the same solid, non-sticky bar (E3); the dashboard keeps its own links (R46). Home icon instead of the wordmark; Users and Sign out live in the profile menu. Header always light for now.
- 2026-10-19 (user): preprod drops basic auth (E2) before AM3; Google sign-in and the invite list gate the dashboard, as on prod.
- 2026-10-19 (user): the Strelitzia homepage demo (E4) is a static mock with made-up data, not screenshots or a public dashboard.
- 2026-10-19 (user): queued plans build, merge and go to preprod with no manual approval (implementer + validator). Prod stays manual.
- 2026-10-19 (user): runner programme PRs auto-merge on green CI.
- 2026-10-19 (user): prod deploys stay the user's, every time; `make prod-changes` shows what the next one ships.
