# Plan: components.toml pins Strelitzia and Wordle; every deploy builds the pinned tags
**Status:** ❌ Not started
**Risk:** review (the prod and preprod deploy path: `scripts/vps/engineerfamily-deploy`, `Makefile`, `scripts/`)
**Depends on:** M4 (Strelitzia and Wordle have `v1.0.0` tags and releases)

## Goal
engineerfamily's git history records which version of each child repo the site runs (user, 2026-10-26). A new
`components.toml` at the repo root pins Strelitzia and Wordle to tags. Every engineerfamily deploy, prod and preprod,
checks out each child at its pin before it builds, so an engineerfamily tag names one exact set of versions: deploying
`v1.6.0` deploys its pins, and rolling back to `v1.5.0` rolls the children back too. A pin change is an ordinary PR
(the runner opens one after each child merge, agent-runner A28; Claude can also raise, hold or pair pins in a plan).
Part 2 (E13, [components-2-release](components-2-release.md)) makes `make prod-release` show and promote the pins.

## Context
- `scripts/vps/engineerfamily-deploy` (whole file, ≈35 lines): root-owned copy in `/usr/local/sbin`, the only thing the
  `deploy` account may run (`deploy|status prod|preprod`); `g()` runs git as `deploy`. It checks out `origin/<env>`, then
  `up -d --build` on the whole stack, which builds `strelitzia` from `../Strelitzia-<env>` and `wordle` from
  `../Wordle-<env>` (compose `build.context`). A change goes live only when the user reinstalls it (M5).
- `Makefile:181-190` `preprod-deploy` (everyday preprod, and what the runner runs for engineerfamily PRs and after
  merges); `Makefile:158-172` `strelitzia-deploy` / `wordle-deploy` (default ref `origin/<base>`).
- The runner's preprod for a *child* PR (`preprod.sh` with Strelitzia's `[preprod] app_dir`) checks out the PR sha in
  `/srv/Strelitzia-preprod` and runs `preprod-strelitzia-up`, not `preprod-deploy`, so pins don't get in its way. Leave
  that path alone.
- All three repos are public: the `deploy` account fetches the children over HTTPS with no credentials. `/srv/Wordle-*` are
  `deploy:srv`, mode 2775, `core.sharedRepository=group` (M1); check `/srv/Strelitzia-*` the same way in Task 2's PR notes
  and list any fix under Left for you (agents never `chown`).
- Gotcha: the root script must not trust paths from the repo. Component names map to `/srv` dirs in the script itself;
  only the tag comes from `components.toml`, and it must match `^v[0-9]+\.[0-9]+\.[0-9]+$`.
- Python 3.11+ is on the host (the runner uses it), so `tomllib` is available; standard library only.

## Tasks
### Task 1: `components.toml` and its reader
**Runs:** unattended
**Files:** components.toml (create), scripts/components.py (create)
**What:** `components.toml`:
```toml
# Which version of each child repo the site runs. Every engineerfamily deploy checks these tags out before it builds.
# The runner opens a "Pin <name> <tag>" PR after each child merge (agent-runner A28); `hold` stops that for one component.
[strelitzia]
repo = "SiddharthEngineer/Strelitzia"
tag = "v1.0.0"
service = "strelitzia"

[wordle]
repo = "SiddharthEngineer/Wordle"
tag = "v1.0.0"
service = "wordle"
# hold = "reason"   # optional: the runner leaves this pin alone and logs the reason
```
`scripts/components.py [--file F]`: `list` → one `name<TAB>repo<TAB>tag<TAB>service` line each; `get <name> <key>`;
`check [--remote]` → exit 1 with one line per problem (unknown key, missing `repo`/`tag`/`service`, a tag not matching the
regex, a name not `[a-z][a-z0-9-]*`); `--remote` also checks each tag exists (`git ls-remote --tags https://github.com/<repo>`).
**Validate:** `python3 scripts/components.py check --remote` → exit 0; `python3 scripts/components.py list` → 2 lines.
**Status:** ❌

### Task 2: deploys check out the pins
**Runs:** unattended
**Files:** scripts/vps/engineerfamily-deploy (modify), Makefile (modify)
**What:** Root script, after the engineerfamily checkout and before compose: for each line of
`runuser -u deploy -- python3 scripts/components.py list` (as `deploy`, never as root), map the name to its dir
(`strelitzia` → `/srv/Strelitzia-<env>`, `wordle` → `/srv/Wordle-<env>`; any other name, or a tag failing the regex, stops the
deploy before anything is built), then as `deploy`: `git -C <dir> fetch -q --prune --tags origin` and
`checkout -q --detach <tag>`; print `→ <name> at <tag>`. A ref without `components.toml` (a rollback to before this plan)
skips the step with a note, leaving the child checkouts as they are. `preprod-deploy` does the same for `/srv/*-preprod`
(as the current user, through a small shared helper target or loop). `strelitzia-deploy` / `wordle-deploy` default to the
pinned tag (`ref=` still overrides, e.g. `ref=origin/trunk` for a hand deploy of the head).
**Validate:** `scripts/validate.sh` passes (`bash -n` covers the root script); `make -n preprod-deploy` shows the
checkouts at the pinned tags (agents can't run `make` against `/srv`: read the recipe and note it in the PR).
**Status:** ❌

### Task 3: validate the pins everywhere
**Runs:** unattended
**Files:** scripts/validate.sh (modify), tests/components-test.sh (create)
**What:** `scripts/validate.sh` gets a `components` step: `components.py check --remote` (CI has network; with
`--offline`, or when `git ls-remote` can't reach GitHub, it falls back to `check` and says so). `tests/components-test.sh`
runs `components.py` against temp files: good file → exit 0 and 2 `list` lines; a bad tag, a missing key, an unknown key and a
bad name each → exit 1 with the problem named. `scripts/validate.sh` runs the test too.
**Validate:** `bash tests/components-test.sh` → one `ok` per case; `scripts/validate.sh` passes.
**Status:** ❌

### Task 4: docs and tracking
**Runs:** unattended
**Files:** agents/DEPLOY.md (modify), AGENTS.md (modify), agents/ROADMAP.md (modify)
**What:** DEPLOY.md: what `components.toml` is, that every deploy builds the pins, that a pin change is a PR (the
runner's bump PRs, `hold`), how preprod for a child PR still runs the PR head, and that `strelitzia-deploy`/`wordle-deploy`
now default to the pin. The `/srv` table: child checkouts sit at pinned tags. AGENTS.md Map and Deploys bullets. ROADMAP:
E12 row, M5 (reinstall the root deploy script).
**Validate:** `scripts/validate.sh` passes.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes, including the new `components` step and test; CI is green.

## Human test steps (preprod)
1. On the VPS after merge: `make preprod-deploy` → `→ strelitzia at v1.0.0` and `→ wordle at v1.0.0`;
   `git -C /srv/Strelitzia-preprod describe --tags` → `v1.0.0`.
2. `https://preprod.engineerfamily.net/strelitzia/privacy` and `https://preprod.engineerfamily.net/wordle/api/health`
   answer 200 (the latter `"ok"`).
3. After M5: the next prod deploy's `deploy.yml` log shows both `→ <name> at <tag>` lines.

## Decisions
1. 2026-10-26 (user): pins live in engineerfamily (`components.toml`), so the site's versions are in its git history and
   Claude can change them through PRs; the user still decides when prod ships.
2. A dedicated `components.toml`, not `pyproject.toml` (engineerfamily isn't a Python package) or git submodules (they pin
   commits, not tags, and fight the detached `/srv` checkouts).
3. The root deploy script maps names to dirs itself and takes only a regex-checked tag from the repo.
4. Preprod for a child PR keeps running that PR's head; only engineerfamily deploys apply the pins.
