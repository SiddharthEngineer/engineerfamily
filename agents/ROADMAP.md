# engineerfamily Roadmap

The single tracker for planned work. Each row links to a plan in `agents/plans/`. Finished plans move to `agents/plans/done/`,
and their history is in git and PRs. Workflow: see the PIV loop in `AGENTS.md`.

Status: ⏳ queued · 🔄 in progress · 🟡 code done, user steps pending · ⏸ blocked · ✅ done (then archived)

## Active

The earlier engineerfamily Parts of the shared-runner programme (ef-validate-ci, ef-agents-layout, ef-runner-config) are tracked
in agent-runner's [ROADMAP](https://github.com/SiddharthEngineer/agent-runner/blob/main/agents/ROADMAP.md) (A5, A12, A13).
New engineerfamily plans go here.

| ID | Initiative | Plan | Risk | Status | Depends on |
|---|---|---|---|---|---|
| E1 | Signed-in header fits on one row on the Strelitzia static pages (Strelitzia R43 follow-up) | [header-fit](plans/header-fit.md) | review | ✅ done | #54 |

## Manual steps (you)

| ID | Step | Done |
|---|---|---|

## Decisions (current)
- 2026-10-19 (user): queued plans build, merge and go to preprod with no manual approval (implementer + validator). Prod stays manual.
- 2026-10-19 (user): runner programme PRs auto-merge on green CI.
- 2026-10-19 (user): prod deploys stay the user's, every time; `make prod-changes` shows what the next one ships.
