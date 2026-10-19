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
| E2 | Preprod without basic auth (Google sign-in only, `noindex`); unblocks agent-runner AM3 | [preprod-open](plans/preprod-open.md) | review | ⏳ planned 2026-10-19 | - |
| E3 | engineerfamily.net header in the Strelitzia page style (part 1; Strelitzia R46 is the dashboard) | [header-style](plans/header-style.md) | review | ⏳ planned 2026-10-19 | - |
| E4 | Strelitzia homepage as a scrollable demo with made-up data | [strelitzia-demo](plans/strelitzia-demo.md) | review | ⏳ planned 2026-10-19 | - |

## Manual steps (you)

| ID | Step | Done |
|---|---|---|

## Decisions (current)
- 2026-10-19 (user): the Strelitzia page's header is the house style; the site header (E3) and the dashboard (Strelitzia R46) follow it.
- 2026-10-19 (user): preprod drops basic auth (E2) before AM3; Google sign-in and the invite list gate the dashboard, as on prod.
- 2026-10-19 (user): the Strelitzia homepage demo (E4) is a static mock with made-up data, not screenshots or a public dashboard.
- 2026-10-19 (user): queued plans build, merge and go to preprod with no manual approval (implementer + validator). Prod stays manual.
- 2026-10-19 (user): runner programme PRs auto-merge on green CI.
- 2026-10-19 (user): prod deploys stay the user's, every time; `make prod-changes` shows what the next one ships.
