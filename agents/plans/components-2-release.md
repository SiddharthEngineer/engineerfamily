# Plan: `make prod-release` ships one engineerfamily tag with its pins and promotes every release it moved
**Status:** 🔄 In progress
**Risk:** review (the prod deploy path: `Makefile`, `scripts/`)
**Depends on:** components-1-pins (E12)

## Goal
One command ships prod (user, 2026-10-26). After E12 an engineerfamily tag already names the Strelitzia and Wordle versions
(`components.toml`), and one `deploy.yml` run builds them all. `make prod-release [v=X.Y.Z] [dry=1]` shows one preview: the
engineerfamily commits since what prod runs, and for each child the pin move (prod's tag → the new tag's pin) with its PRs.
It also warns about child tags not pinned yet (an open bump PR). It asks one `Ship <tag> to prod? [y/N]`, deploys,
health-checks the site and each child, and only then promotes the engineerfamily release and the release of each child
whose pin moved. Rollback is `make deploy-prod ref=<older tag>`, which now rolls the children back too.

## Context
- `Makefile:249-275` `prod-release` (inlined today: sync → pick tag → `prod-changes.sh` → y/N → `gh workflow run deploy.yml`
  → find the run, 30 × 2 s → `gh run watch` → `versions promote engineerfamily`). Move it into `scripts/prod-release.sh`;
  keep the run-finding loop as it is.
- `scripts/prod-changes.sh` (whole file, ≈90 lines): engineerfamily = newest full release's tag..origin/main; Strelitzia and
  Wordle = `/srv/<Repo>-prod` HEAD..origin/<base>. `log_with_links` and `pr_of` are reused.
- E12's `scripts/components.py list [--file F]`. A tag's pins: `git show <tag>:components.toml` into a temp file.
- Health after the deploy (6 tries, 10 s apart, like agent-runner's `preprod.sh`): `https://engineerfamily.net/healthz` →
  200; `$(PROD) exec -T strelitzia curl -fsS http://127.0.0.1:8000/strelitzia/dashboard/api/health` (Strelitzia's image has
  curl; the dashboard is behind the Site gate through Cloudflare, and prod has no 127.0.0.1:8080 health server);
  `https://engineerfamily.net/strelitzia/privacy` → 200; `https://engineerfamily.net/wordle/api/health` → JSON `ok`.
- Open bump PRs (agent-runner A28): `gh pr list --repo SiddharthEngineer/engineerfamily --label pin-bump --state open`.
- Agents can't run `make prod-release`, `deploy-prod` or `versions promote` (denied in `.claude/settings.json`). Test against
  temp git repos with stub `gh`, `agent-runner`, `curl` and `docker` on `PATH`, never `/srv`, the real `gh` or the runner.

## Tasks
### Task 1: what would ship
**Runs:** unattended
**Files:** scripts/prod-changes.sh (modify)
**What:** `prod-changes.sh [<target tag>]` (default: the newest `vX.Y.Z`): engineerfamily `prod tag → target` with the
log as today, plus `not in it:` (`<target>..origin/main`, first-parent, omitted when empty). Then per component in the
target's `components.toml`: prod's tag (`git -C /srv/<Repo>-prod describe --tags --exact-match`, else short sha) → the
pin, with `log_with_links` over that range from the dev clone, or `nothing new`. Then `not pinned yet:` for each child tag
newer than the pin, naming the open `pin-bump` PR if there is one. `--plan` prints only `name<TAB>prod_ref<TAB>pin<TAB>new|same|older`
lines (engineerfamily first) for Task 2. A target older than prod's engineerfamily tag prints `older`.
**Validate:** `bash -n scripts/prod-changes.sh`; Task 3's test covers the output.
**Status:** ✅ 2026-10-27 (this commit)

### Task 2: `scripts/prod-release.sh`
**Runs:** unattended
**Files:** scripts/prod-release.sh (create), Makefile (modify)
**What:** `make prod-release [v=X.Y.Z] [dry=1]` runs the script (the Makefile passes `PROD`, `GH`, the `/srv` dirs).
(1) `agent-runner versions sync` for engineerfamily, strelitzia and wordle; exit 3 or 4 stops with the M4 hint. (2) Pick
`v` or the newest tag; `prod-changes.sh --plan`: engineerfamily `older` → refused (rollbacks are `make deploy-prod ref=…`);
everything `same` → "Nothing to ship." exit 0. (3) The full preview and one `Ship <tag> to prod? [y/N]`. (4) The
`deploy.yml` trigger and run watch as today; a failed run promotes nothing. (5) The Context health checks; a failure
promotes nothing and prints `make deploy-prod ref=<prod's previous tag>`. (6) `versions promote engineerfamily <tag>`, then
`versions promote <child> <pin>` for each child that was `new`. Print `✓ <tag> on prod: strelitzia <pin>, wordle <pin>`.
`dry=1`: sync with `--dry-run`, the preview, and the commands it would run; no prompt.
**Validate:** `bash -n scripts/prod-release.sh`; `make -n prod-release` prints the script call; Task 3's test passes.
**Status:** ❌

### Task 3: test it without prod
**Runs:** unattended
**Files:** tests/prod-release-test.sh (create), scripts/validate.sh (modify)
**What:** Temp origin repos for the three (engineerfamily tags carrying different `components.toml` pins; a full release
faked through a stub `gh`), temp "prod" clones at older tags, and logging stubs. Cases: (a) only Strelitzia's pin moved →
one deploy, then promotes for engineerfamily and strelitzia only; (b) both pins moved → both children promoted;
(c) answer `n` → no deploy, no promote; (d) a health check fails → no promote, rollback hint names prod's old tag;
(e) `v=<older tag>` → refused before the prompt; (f) sync exit 3 for wordle → stops with the hint; (g) `dry=1` → no deploy
or promote calls; (h) a child tag newer than the pin with an open `pin-bump` PR → `not pinned yet` names it.
`scripts/validate.sh` gets a `prod-release test` step.
**Validate:** `bash tests/prod-release-test.sh` → 8 `ok` lines; `scripts/validate.sh` passes.
**Status:** ❌

### Task 4: docs and tracking
**Runs:** unattended
**Files:** agents/DEPLOY.md (modify), AGENTS.md (modify), agents/ROADMAP.md (modify)
**What:** DEPLOY.md's prod section: one command, the preview, health checks, which releases get promoted, `dry=1`, and
rollback (`deploy-prod ref=` moves the children too and promotes nothing). `strelitzia-deploy`/`wordle-deploy` are for
hand fixes only, and leave prod off its pins until the next deploy. AGENTS.md's Deploys bullet (drop "The Strelitzia
dashboard ships on its own"). ROADMAP: E13 row.
**Validate:** `scripts/validate.sh` passes.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes (including `prod-release test`); CI is green.

## Human test steps (preprod)
Preprod can't exercise a prod deploy, so these are yours on the VPS after the merge (and M5):
1. `make prod-changes` → an engineerfamily section, then `strelitzia: <prod tag> → <pin>` and `wordle: …` (or `nothing new`).
2. `make prod-release dry=1` → the same preview and the commands it would run; no prompt; `agent-runner versions status
   strelitzia` is unchanged.
3. When something is waiting: `make prod-release`, `y` → `✓ <tag> on prod: …`; `git -C /srv/Strelitzia-prod describe --tags`
   → the pin; GitHub shows a new Latest release for engineerfamily and for each child whose pin moved.

## Decisions
1. 2026-10-26 (user): extend `prod-release`; one preview and one y/N.
2. One engineerfamily tag is the site's version; children ship through its pins, not separate deploys.
3. Promote only after the deploy and every health check pass, so no release names a version that isn't on prod.
4. A target older than prod is refused: rollbacks stay `make deploy-prod ref=…`, which promotes nothing.
