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
| E3 | engineerfamily.net header in the Strelitzia page style (part 1; Strelitzia R46 is the dashboard) | [header-style](plans/header-style.md) | review | ⏳ queued 2026-10-21 (1st, then Strelitzia R46) | - |
| E4 | Strelitzia homepage as a scrollable demo with made-up data | [strelitzia-demo](plans/strelitzia-demo.md) | review | ⏳ queued 2026-10-21 (after Strelitzia R46) | Strelitzia R46 (queue order) |
| E5 | Wordle solver 1/3: vectorized solver core, tests, CI (Wordle repo, cross-repo PR) | [wordle-solver-1-core](plans/wordle-solver-1-core.md) | low | ⏸ 2026-10-22: solver and tests in Wordle PR #1 (open); CI workflow blocked (the token has no `workflow` scope; asked the user) | M1 |
| E6 | Wordle solver 2/3: tile-grid page, FastAPI, Docker image (Wordle repo, cross-repo PR) | [wordle-solver-2-web](plans/wordle-solver-2-web.md) | low | ⏳ planned 2026-10-20 | E5 |
| E7 | Wordle solver 3/3: `wordle` service, nginx `/wordle/`, make targets, home link | [wordle-solver-3-deploy](plans/wordle-solver-3-deploy.md) | review | ⏳ planned 2026-10-20 | E6, M1 |
| E8 | Site permissions 1/4: `engineerfamily` DB, per-page grants, admin API, `/auth/verify?page=` | [site-perms-1-store](plans/site-perms-1-store.md) | review | ⏳ planned 2026-10-21 | E4 (queue order) |
| E9 | Site permissions 2/4: admin-only Users page at `/users/`, profile-menu link | [site-perms-2-users-page](plans/site-perms-2-users-page.md) | review | ⏳ planned 2026-10-21 | E8, E3 |
| E10 | Site permissions 3/4: nginx enforces Site + per-page access, no-access pages | [site-perms-3-gate](plans/site-perms-3-gate.md) | review | ⏳ planned 2026-10-21 | E9, M2 (preprod half) |

## Manual steps (you)

| ID | Step | Done |
|---|---|---|
| M1 | Give the VPS runner's token push access to SiddharthEngineer/Wordle and enable "Allow auto-merge" there (before E5). Create `/srv/Wordle-prod`, `/srv/Wordle-preprod` (deploy:srv) and `~/src/Wordle` before E7's first preprod or prod deploy. Done 2026-10-21: token push checked (test branch made and deleted), auto-merge on (user); `/srv/Wordle-{prod,preprod}` (deploy:srv, 2775, `core.sharedRepository=group`, in `safe.directory`) and `~/src/Wordle` cloned over HTTPS at `main` | ☑ |
| M2 | Site permissions DB and seed list (after E8 merges, before E10 runs). Preprod: in `/srv/engineerfamily-preprod/.env` add `SITE_DB_PASSWORD_PREPROD=` (`openssl rand -hex 24`) and `SITE_ADMIN_EMAILS=` your Gmail and the dev test account's (comma-separated), then `make preprod-site-db-init` and `make preprod-deploy`. Prod, before the first prod deploy with E8-E10: `SITE_DB_PASSWORD=`, `SITE_ADMIN_EMAILS=` your Gmail, `SITE_MEMBER_EMAILS=` the dev test account, then `make site-db-init`. After prod is live, re-invite the existing Strelitzia users on `/users/`. | ☐ |

## Decisions (current)
- 2026-10-21 (user): engineerfamily owns site access: a Users page with per-page grants (Site, Strelitzia + cap, Bracket Analyzer, …), admins, and an Everyone row (prod: Site; preprod: nothing). Postgres DB; seed emails only in `/srv` `.env`; existing Strelitzia users re-invited by hand (E8-E10, Strelitzia R47).
- 2026-10-20 (user): the Wordle solver lives at `engineerfamily.net/wordle/`, public, as a FastAPI container built from the Wordle repo like Strelitzia; app code in Wordle, infra in engineerfamily; Wordle PRs auto-merge on green CI.
- 2026-10-19 (user): the Strelitzia page's header is the house style; the site header (E3) and the dashboard (Strelitzia R46) follow it.
- 2026-10-19 (user): preprod drops basic auth (E2) before AM3; Google sign-in and the invite list gate the dashboard, as on prod.
- 2026-10-19 (user): the Strelitzia homepage demo (E4) is a static mock with made-up data, not screenshots or a public dashboard.
- 2026-10-19 (user): queued plans build, merge and go to preprod with no manual approval (implementer + validator). Prod stays manual.
- 2026-10-19 (user): runner programme PRs auto-merge on green CI.
- 2026-10-19 (user): prod deploys stay the user's, every time; `make prod-changes` shows what the next one ships.
