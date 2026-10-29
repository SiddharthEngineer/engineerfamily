# Plan: preprod floats on the children's newest tags; `components.toml` pins prod and only `make prod-release` moves it
**Status:** ✅ Done 2026-10-29
**Risk:** review (the prod release path: `scripts/prod-release.sh`, `Makefile`)
**Depends on:** E12 [components-1-pins](components-1-pins.md), E13 [components-2-release](components-2-release.md);
agent-runner A33 [runner-18-float-pins](https://github.com/SiddharthEngineer/agent-runner/blob/main/agents/plans/runner-18-float-pins.md)
installed and AM11 done (runner.toml passes `ref={branch}` / `ref=main`)
**Queue:** after agent-runner/runner-18-float-pins (queued by hand 2026-10-28)

## Goal
User, 2026-10-28: "prod pinned in Git, preprod floating", and "preprod deploys always require either a tag or branch".
- **Preprod floats.** `make preprod-deploy` checks each child out at its newest `vX.Y.Z` tag on GitHub, not at the
  `components.toml` pin. `strelitzia=<tag|branch>` / `wordle=<tag|branch>` override one child (pair an engineerfamily branch
  with a child branch); an optional `preprod = "<tag|branch>"` key in a component freezes preprod on it.
- **Every preprod deploy names a tag or a branch.** `ref=` is required and must be a `vX.Y.Z` tag or a branch (`main`,
  `agent/x`, `origin/agent/x`); a sha, `HEAD~1` or anything else is refused before anything is checked out. The same rule
  for the child overrides, the `preprod` key, and `make preprod-wordle-deploy`.
- **Prod stays pinned in Git.** `components.toml`'s `tag` is what prod runs. `make prod-release` is the only thing that
  moves it: when a child has a newer tag than main's pin (and no `hold`), the preview shows the move, and after the one
  `y` it merges a single "Release pins: strelitzia vA, wordle vB" PR, tags it (`agent-runner versions sync`), and ships that
  tag. One commit per prod release instead of one per child merge.

## Context
- `Makefile:33-52` `checkout-pins` and `pin`; `Makefile:198-212` `preprod-deploy`; `Makefile:235-240` `preprod-wordle-deploy`
  (defaults to `origin/main`, takes a sha today). `strelitzia-deploy`/`wordle-deploy` (prod hand fixes) keep reading the prod pin.
- `scripts/components.py`: `list`/`get`/`check`; `KEYS` (add `preprod`), `TAG_RE`. Add
  `set <name> tag <vX.Y.Z>` that rewrites only that component's `tag = "…"` line (comments and order kept; agent-runner's
  old `pins.py` had the same text edit) and `newest <name>` (newest `vX.Y.Z` tag via `git ls-remote --tags`).
- `scripts/prod-release.sh:1-149` (steps in its header) and `scripts/prod-changes.sh:70-192` (the per-child preview,
  `not pinned yet:` and `pin_pr` lookups of open `pin-bump` PRs: replace with "newest tag, pinned by this release").
- `tests/prod-release-test.sh`: temp origins with tagged pins and stubbed `gh`/`agent-runner`; extend it.
- `scripts/site-version.sh` (preprod label: tag, else branch, else `vX.Y.Z+N`, else sha): no change needed once refs are
  tags or branches; check it labels `ref=agent/x` as the branch.
- `agents/DEPLOY.md:43-112` (pins, deploying, prod-release, rollback); `AGENTS.md` if it mentions pin PRs.
- engineerfamily merges with `merge`; `gh pr checks <n> --watch` then `gh pr merge <n> --merge --delete-branch`. The release
  PR is made by the user's own `gh` login when they run `make prod-release`.
- Gotcha: the runner deploys preprod with this repo's `agents/runner.toml` from main. Until AM11 it passes `ref={sha}` and no
  `ref` on release, which this plan refuses, so Task 0 checks AM11 first.

## Tasks
### Task 0: check the starting point
**Runs:** unattended
**Files:** none
**What:** `git show origin/main:agents/runner.toml` has `ref={branch}` in `[preprod] deploy` and `ref=main` in `release`, and
`agent-runner version` is at or past the release with A33 (`agent-runner pins` is gone). If not, stop with a question for
the user: "install the runner with A33 and do agent-runner AM11 first".
**Validate:** both true.
**Status:** ✅ 2026-10-29: runner.toml on main has ref={branch} and ref=main (#96); agent-runner v0.2.12, no `pins`

### Task 1: refs must be a tag or a branch; preprod floats
**Runs:** unattended
**Files:** Makefile (modify), scripts/components.py (modify), scripts/preprod-ref.sh (new), tests/components-test.sh or the
existing components tests (modify)
**What:** `scripts/preprod-ref.sh <git dir> <ref>`: fetch tags and branches, then print the ref to check out
(`refs/tags/vX.Y.Z` or `refs/remotes/origin/<branch>`, accepting `main`, `agent/x` and `origin/agent/x`), or exit 2 with
`preprod: <ref> is not a vX.Y.Z tag or a branch on origin`. `preprod-deploy` with no `ref=` exits with
`preprod-deploy needs ref=<tag|branch> (e.g. ref=main)`. A preprod `checkout-pins` variant per child: the
`strelitzia=`/`wordle=` override, else the component's `preprod` key, else `components.py newest <name>`; each goes
through `preprod-ref.sh`, and prints `→ <name> at <ref> (newest|override|preprod key)`. Prod's checkout of the pins is
unchanged. `preprod-wordle-deploy` uses the same resolver (default: newest tag).
**Validate:** the components tests: a sha, `HEAD~1` and a missing branch are refused with exit 2 before any checkout;
`main`, `origin/agent/x` and `v1.2.3` resolve; `preprod-deploy` without `ref` fails; the float picks the newest tag;
an override and a `preprod` key win in that order. `scripts/validate.sh --offline` passes.
**Status:** ✅ 2026-10-29 (this commit)

### Task 2: `make prod-release` moves the pins
**Runs:** unattended
**Files:** scripts/prod-release.sh (modify), scripts/prod-changes.sh (modify), scripts/components.py (modify),
tests/prod-release-test.sh (modify)
**What:** after step 1 (versions sync), for each component without `hold`: `newest` > main's pin → a pending move. With moves
and no `vX.Y.Z` argument: the preview (`prod-changes.sh`) shows each child `prod's tag → newest` with its PRs, plus
engineerfamily's commits on main since prod's tag; one `Ship to prod? [y/N]`. On `y`: branch `release/pins-<UTC date>`
from `origin/main`, `components.py set` per move, commit `Release pins: strelitzia vA, wordle vB`, push, `gh pr create`
(label `release-pins`), `gh pr checks --watch`, `gh pr merge --merge --delete-branch`, `agent-runner versions sync
engineerfamily`, then deploy the new tag as today (steps 4-6). Red CI or a failed merge stops before any deploy and says
which PR. With an explicit `v=X.Y.Z`, ship that tag's pins as today (no moves). `--dry-run`: the preview and the commands,
no branch. `hold` children are listed as `held: <reason>`. Drop the `pin-bump` PR lookups.
**Validate:** `bash tests/prod-release-test.sh`: a newer child tag → one release PR changing only tag lines, merged, tagged,
deployed; nothing newer and engineerfamily unchanged → "Nothing to ship."; red CI → nothing deployed or promoted; `v=`
skips the moves; `hold` respected; dry run creates nothing.
**Status:** ✅ 2026-10-29 (this commit)

### Task 3: docs and tracking
**Runs:** unattended
**Files:** agents/DEPLOY.md (modify), AGENTS.md (modify), components.toml (comments only), agents/ROADMAP.md (modify)
**What:** DEPLOY.md: "Child repo pins" says `tag` is prod's version and only `prod-release` moves it; preprod floats on the
newest tags with the overrides and the `preprod` key; `preprod-deploy` needs `ref=<tag|branch>` (examples:
`ref=main`, `ref=agent/x`, `ref=v1.6.6`); the prod-release steps gain the release-pins PR. `components.toml`'s header
comment says the same (no more "the runner opens a Pin PR"). ROADMAP: E15 ✅.
**Validate:** `scripts/validate.sh` passes.
**Status:** ✅ 2026-10-29 (this commit)

## Validation
- `scripts/validate.sh` passes; CI is green.

## Human test steps
1. `make -C ~/src/engineerfamily preprod-deploy` → refused, asks for `ref=`. `… ref=$(git rev-parse HEAD)` → refused.
2. `… preprod-deploy ref=main` → prints `→ strelitzia at v<newest> (newest)`; the site header shows main's version.
3. `make prod-release dry=1` → each child's move from prod's tag to its newest tag, and the release-pins commands; nothing created.
4. Next real release: `make prod-release`, `y` → one "Release pins: …" PR merged, a new engineerfamily tag, prod on it.

## Decisions
1. 2026-10-28 (user): prod pinned in Git, preprod floating; every preprod deploy requires a tag or a branch.
2. Float to the newest tag, not `vX.Y.latest`: children start a new minor right after each prod release, so a minor pin
   would need a commit after every release anyway.
3. One release-pins PR per prod release, made by `prod-release` itself, so the engineerfamily tag still names exact versions
   and rollback (`make deploy-prod ref=<older tag>`) still rolls the children back.
