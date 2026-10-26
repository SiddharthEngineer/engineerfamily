# Plan: `make prod-release` ships engineerfamily, Strelitzia and Wordle at their tags
**Status:** ❌ Not started
**Risk:** review (the prod deploy path: `Makefile`, `scripts/`)
**Depends on:** M4 (Strelitzia and Wordle get `[release]`, their first tags and releases); E11 [site-version](done/site-version.md)

## Goal
One command ships prod (user, 2026-10-26). `make prod-release` tags any untagged merges in all three repos, shows one
preview (per repo: what prod runs → the tag it would ship, with PR links, and what's on the base but not in that tag),
skips repos with nothing new, asks one `Ship to prod? [y/N]`, then deploys engineerfamily, Strelitzia and Wordle in that
order. Each repo is health-checked and its GitHub release promoted only after its own deploy passes; the first failure
stops the run and says what shipped and what didn't. Strelitzia and Wordle ship tags, not branch heads, so every prod
deploy of any repo is a version with a release.

## Context
- `Makefile:249-275` `prod-release`: today engineerfamily only, inlined (sync → pick tag → `prod-changes.sh` → y/N →
  `gh workflow run deploy.yml` → find the run (30 × 2 s) → `gh run watch` → `versions promote`). Move the logic into a
  script; keep that run-finding loop as it is.
- `Makefile:158-172` `strelitzia-deploy` / `wordle-deploy`: `git fetch` + `checkout --detach $(or $(ref),origin/<base>)`
  in `/srv/<Repo>-prod`, then `$(PROD) up -d --build --force-recreate --no-deps <service>`. They stay (hand deploys and
  rollbacks); the new script calls them with `ref=<tag>`. Their fetch needs `--tags` so a fresh tag can be checked out.
- `scripts/prod-changes.sh` (whole file, ≈90 lines): engineerfamily range = newest full release's tag..origin/main;
  Strelitzia and Wordle = `/srv/<Repo>-prod` HEAD..origin/<base> from the dev clones (`STRELITZIA_DEV_DIR`,
  `WORDLE_DEV_DIR`). `log_with_links` and `pr_of` are reused.
- Order matters: `scripts/vps/engineerfamily-deploy` runs `up -d --build` on the whole stack, which rebuilds `strelitzia`
  and `wordle` from whatever `/srv/<Repo>-prod` holds. engineerfamily goes first (nginx routes, the Site gate and DBs are
  what Strelitzia and Wordle rely on, e.g. site-perms-3 before site-perms-4), then Strelitzia, then Wordle.
- Health after each deploy. engineerfamily: `deploy.yml` already runs `status prod`; add `https://engineerfamily.net/healthz`
  → 200. Strelitzia: `$(PROD) exec -T strelitzia curl -fsS http://127.0.0.1:8000/strelitzia/dashboard/api/health`
  (Strelitzia's Dockerfile has curl and that healthcheck; prod has no 127.0.0.1:8080 health server and the dashboard is
  behind the Site gate through Cloudflare) and `https://engineerfamily.net/strelitzia/privacy` → 200. Wordle:
  `https://engineerfamily.net/wordle/api/health` → JSON `ok`. 6 tries, 10 s apart, like agent-runner's `preprod.sh`.
- `agent-runner versions sync|promote|status <repo>` (agent-runner `versions.py`): exit 3 = waiting for a bootstrap
  promote, 4 = repo has no `[release]`. Repo names: `engineerfamily`, `strelitzia`, `wordle` (M4 registers `wordle`).
- Agents can't run `make prod-release`, `deploy-prod` or `versions promote` (denied in `.claude/settings.json`). Test the
  script against temp git repos and stub commands on `PATH`, never the real `/srv` checkouts, `gh` or `agent-runner`.

## Tasks
### Task 1: what would ship
**Runs:** unattended
**Files:** scripts/prod-changes.sh (modify)
**What:** Per repo, the range is *prod → target tag*: engineerfamily as today (newest full release's tag, fallbacks
unchanged); Strelitzia and Wordle from `/srv/<Repo>-prod` HEAD (`git describe --tags --exact-match` for the label, else
the short sha). Target = `EF_TAG` / `STRELITZIA_TAG` / `WORDLE_TAG` env vars when set, else the repo's newest `vX.Y.Z` tag.
Print, per repo, `<repo>: <prod label> → <target>` and the log with links, or `<repo>: nothing new (prod runs <tag>)`
when prod's commit is the target's commit, then `  not in it:` with `<target>..origin/<base>` (first-parent, omitted when
empty). With `--plan` it prints only machine-readable lines `repo<TAB>prod_sha<TAB>target_tag<TAB>new|same|older`
(older = the target is an ancestor of prod's commit) for the script in Task 2. `make prod-changes` keeps working, now
comparing prod with the newest tags.
**Validate:** `bash -n scripts/prod-changes.sh`; Task 3's test covers the output.
**Status:** ❌

### Task 2: `scripts/prod-release.sh` and the make target
**Runs:** unattended
**Files:** scripts/prod-release.sh (create), Makefile (modify)
**What:** `make prod-release [v=X.Y.Z] [strelitzia=X.Y.Z] [wordle=X.Y.Z] [dry=1]` runs
`scripts/prod-release.sh` (the Makefile passes `PROD`, `GH`, the `/srv` dirs). A repo value of `skip` holds that repo back.
Steps: (1) `agent-runner versions sync <repo>` for each of the three; exit 3 or 4 for a repo stops with the bootstrap hint
from M4 (no repo is silently left out). (2) `prod-changes.sh --plan` with the chosen targets; an `older` target is refused
("rollbacks: `make deploy-prod ref=…` / `make strelitzia-deploy ref=…` / `make wordle-deploy ref=…`"); `same` repos are
skipped; nothing `new` → "Nothing to ship." exit 0. (3) Print the full `prod-changes.sh` preview and one
`Ship to prod: engineerfamily v1.5.0, strelitzia v1.1.0? [y/N]`. (4) In order engineerfamily → strelitzia → wordle, for each
`new` repo: deploy (engineerfamily: the existing workflow trigger + run watch; the others: `$(MAKE) <repo>-deploy ref=<tag>`),
the Context health checks, then `agent-runner versions promote <repo> <tag>`. On a failed deploy or health check: stop,
promote nothing for that repo, and print `shipped: …`, `failed: <repo> <tag> (<why>)`, `not shipped: …` and that repo's
rollback command with the tag prod ran before. `dry=1` runs sync with `--dry-run`, prints the preview and each command it
would run, and asks nothing. `strelitzia-deploy` and `wordle-deploy` fetch with `--tags`.
**Validate:** `bash -n scripts/prod-release.sh`; `make -n prod-release` prints the script call; Task 3's test passes.
**Status:** ❌

### Task 3: test it without prod
**Runs:** unattended
**Files:** tests/prod-release-test.sh (create), scripts/validate.sh (modify)
**What:** A bash test that builds three temp origin repos with tags (engineerfamily with a full release faked through a
stub `gh`), temp "prod" clones detached at older tags, and stubs on `PATH` for `gh`, `agent-runner`, `curl`, `docker` and
`make` that log their arguments. Cases: (a) Strelitzia new, others same → only Strelitzia deployed, health-checked and
promoted, in that order; (b) all new → order engineerfamily, strelitzia, wordle; (c) answer `n` → nothing deployed or
promoted; (d) Strelitzia's health check fails → wordle not deployed, no strelitzia promote, rollback hint names prod's old
tag; (e) `strelitzia=<older tag>` → refused before the prompt; (f) `versions sync` exit 3 for wordle → stops with the hint;
(g) `dry=1` → no deploy or promote calls; (h) `wordle=skip` → wordle untouched. `scripts/validate.sh` gets a
`prod-release test` step running it.
**Validate:** `bash tests/prod-release-test.sh` → one `ok` per case, exit 0; `scripts/validate.sh` passes.
**Status:** ❌

### Task 4: docs and tracking
**Runs:** unattended
**Files:** agents/DEPLOY.md (modify), AGENTS.md (modify), agents/ROADMAP.md (modify)
**What:** DEPLOY.md's prod section: `make prod-release` ships all three repos at their tags (the preview, one y/N, order,
per-repo health and promote, stop on first failure, `skip`/overrides, `dry=1`); `strelitzia-deploy`/`wordle-deploy`/
`deploy-prod` are for rollbacks and hand fixes, and a hand deploy of a branch head leaves that repo off its release until
the next `prod-release`. The `/srv` table says Strelitzia-prod and Wordle-prod sit at tags. AGENTS.md's Deploys bullet
likewise. ROADMAP: E12 row.
**Validate:** `scripts/validate.sh` passes.
**Status:** ❌

## Validation
- `scripts/validate.sh` passes (including the new `prod-release test` step); CI is green.
- `bash tests/prod-release-test.sh` → 8 `ok` lines.

## Human test steps (preprod)
Preprod can't exercise a prod deploy, so these are all yours, on the VPS after the merge (and M4):
1. `make prod-changes` → three sections, each `prod <tag> → <newest tag>` or `nothing new (prod runs <tag>)`.
2. `make prod-release dry=1` → the same preview, then the commands it would run, in the order engineerfamily → strelitzia
   → wordle, and no prompt. Nothing changes: `agent-runner versions status strelitzia` is the same before and after.
3. When something is waiting: `make prod-release`, answer `y` → each repo deploys, `✓ <repo> <tag> healthy, release
   promoted`; then `git -C /srv/Strelitzia-prod describe --tags` → the shipped tag, and GitHub shows `v1.1` (or the next
   minor) as Latest for each repo that shipped.

## Decisions
1. 2026-10-26 (user): extend `prod-release` rather than add a new target; one preview and one y/N for all repos.
2. 2026-10-26 (user): Wordle gets tags too (its own `runner.toml` with `[release]`, registered as `wordle`).
3. 2026-10-26 (user): Strelitzia and Wordle start at `v1.0.0` on the commit prod runs now (Strelitzia `bdca7b3`, Wordle `3a0ccf2`).
4. engineerfamily deploys first, because its nginx routes, Site gate and DBs are what the other two depend on.
5. A target older than prod is refused: rollbacks stay explicit, per-repo commands that promote nothing.
6. Each repo is promoted only after its own deploy and health check, so a GitHub release never names a version that isn't on prod.
