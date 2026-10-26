# engineerfamily deploys

How engineerfamily releases and deploys work: versions and releases, the header's version text, preprod and prod deploys, the deploy workflow, and
the VPS layout. Moved here from `README.md` on 2026-10-19 (ef-agents-layout). Prod deploys are always the user's call.
Before a prod deploy, `make prod-changes` shows what will ship.

### Versions and releases

Since E11 (2026-10-23) versions come from the runner (agent-runner `versions`, on through `[release]` in
`agents/runner.toml`), not from hand-made tags:

1. **Every PR merged to `main` gets the next patch tag**, `v1.4.2` → `v1.4.3`, and the GitHub pre-release `v1.4` moves
   to it, its notes listing every patch and PR in the minor.
2. **`make prod-release` deploys a tag and promotes its release** (below): `v1.4` becomes a full, Latest release.
3. **The next merge starts the next minor**: `v1.5.0` and a new `v1.5` pre-release. Major bumps stay by hand
   (`agent-runner versions promote … --next-major`).

Plan or doc commits pushed straight to `main` get no tag. The old `v*-preprod` tags and `release-v*` branches stay as
history; nothing creates them any more.

`prod` is the deployment state branch: it points to what prod runs, and the deploy workflow moves it. The `preprod`
branch is just the local branch name in `/srv/engineerfamily-preprod`; `git -C /srv/engineerfamily-preprod log -1` is
the source of truth for what preprod runs.

#### What the header shows

Every deploy writes `services/shared/version.json` (`{"label", "url"}`, gitignored) with `scripts/site-version.sh`, and
`<ef-profile>` in `services/shared/site-header.js` shows it in small muted text just left of the avatar (or Sign in), on
every page including the Strelitzia dashboard. It links to GitHub:

| Where | Shows | Links to |
|---|---|---|
| prod, at a tag | `v1.4` (the minor) | that tag's release |
| preprod, at a tag | `v1.4.2` | that tag's release |
| preprod, on a PR branch | `agent/site-version` | the branch's PRs |
| preprod, on `main` past a tag | `v1.4.2+3` (3 untagged commits) | the compare view from the tag |
| anything else | the short sha | the commit |

It shows as its own section of the avatar menu (signed in only), between the name/email and the links. No
`version.json` (local dev, or prod before the deploy script is reinstalled) means no version section. The header fetches
it once per page with `cache: 'no-store'`, so a deploy shows up on the next page load.

### Child repo pins (`components.toml`)

`components.toml` at the repo root pins each child repo (Strelitzia, Wordle) to a tag. Every engineerfamily deploy, prod
and preprod, checks each child out at its pin in `/srv/<Repo>-<env>` before it builds, and prints `→ <name> at <tag>`. So an
engineerfamily tag names one exact set of versions: deploying it deploys its pins, and rolling back rolls the children back
too. A ref from before the pins (no `components.toml`) leaves the child checkouts as they are.

- **A pin change is an ordinary PR.** The runner opens a `Pin <name> <tag>` PR after each child merge (agent-runner A28);
  `hold = "reason"` on a component stops that for it. A plan can also raise, hold or pair pins.
- **Reading them:** `python3 scripts/components.py list` (or `get <name> tag`); `check [--remote]` is the validation
  `scripts/validate.sh` runs (`--offline` skips checking the tags exist on GitHub).
- **Preprod for a child PR** still runs that PR's head: the runner's `preprod.sh` checks the PR sha out in
  `/srv/<Repo>-preprod` and rebuilds only that service, without `preprod-deploy`. The next `preprod-deploy` puts the pin back.
- **`make strelitzia-deploy` / `make wordle-deploy`** default to the pin in `/srv/engineerfamily-prod/components.toml`;
  `ref=` still overrides (e.g. `ref=origin/trunk` for a hand deploy of the head).
- The root deploy script maps component names to `/srv` dirs itself and takes only a `vX.Y.Z` tag from the repo.

### Deploying

#### Preprod Deploy

Run on the VPS, from any directory (e.g. the dev clone):

```bash
make preprod-deploy                     # origin/main
make preprod-deploy ref=origin/my-branch # a pushed branch, before merging
make preprod-deploy ref=<sha|tag>
```

It checks that commit out in `/srv/engineerfamily-preprod`, checks the children out at its pins, writes `version.json`, rebuilds the stack
(`up -d --build --remove-orphans`) and recreates nginx. Push the commit first, because it deploys what is on GitHub.
The runner deploys each PR's head this way, and `main` again after a merge (once the tag exists, so the header shows it).

#### Prod Deploy

Prod deploys are always a tag, and always the user's call:

```bash
make prod-release            # the newest tag; or: make prod-release v=1.4.3
```

It runs `agent-runner versions sync engineerfamily` (tags any merge not tagged yet), picks the tag, shows
`make prod-changes` (the commits since the newest full release, plus Strelitzia and Wordle since what prod runs, with PR
links), asks `Deploy <tag> to prod? [y/N]`, triggers `deploy.yml`, waits for the run (`gh run watch`), and only if it
succeeds runs `agent-runner versions promote engineerfamily <tag>`. A failed deploy promotes nothing.

**Rollback:** `make deploy-prod ref=<older tag>`. It triggers the same workflow and promotes nothing, so the Latest
release keeps naming the version you rolled back from until the next `prod-release`.

Merging to `main` never ships prod: until the next `prod-release`, prod keeps running its tag. Check with
`git -C /srv/engineerfamily-prod describe --tags`, and compare with `git describe --tags origin/main`.
The `prod` branch in `/srv/engineerfamily-prod` (tracking `origin/prod`) belongs to the deploy script, which recreates it on
every deploy. Don't `git pull` there: it can only bring in what the last deploy pushed to `origin/prod`.

#### Site permissions setup (ROADMAP M2)

The site permissions (README.md, **Site permissions**) need their DB and `.env` values in each env. Until then the app
runs in env-only mode, and with no admin anywhere everyone keeps Site, so nothing locks up; but nobody can grant
anything. Real addresses go only in the `/srv` `.env` files, never in the repo, an issue or a PR.

1. Preprod, in `/srv/engineerfamily-preprod/.env`: `SITE_DB_PASSWORD_PREPROD=` (`openssl rand -hex 24`) and
   `SITE_ADMIN_EMAILS=` (comma-separated), then `make preprod-site-db-init` and `make preprod-deploy`.
2. Prod, **before the first prod deploy containing site-perms parts 1-3** (the nginx gate ships in part 3): in
   `/srv/engineerfamily-prod/.env` `SITE_DB_PASSWORD=`, `SITE_ADMIN_EMAILS=` and `SITE_MEMBER_EMAILS=`, then
   `make site-db-init` from the dev clone at `origin/main` (`git pull` first). It runs the clone's
   `scripts/init-site-db.sh` with prod's `.env` and compose files, so it works while prod still runs a tag from before
   the script (v1.4.0); it only creates the role and database in the running `postgres-db`. The emails seed an empty DB
   once, when the new app first starts; after that `/users/` decides. List every current Strelitzia user in
   `SITE_MEMBER_EMAILS` (members get every page, Strelitzia included): once the gate is live, anyone not listed loses
   the dashboard. Prod's Everyone row starts with Site, so the public site stays open.
3. Check from outside: signed out, `https://preprod.engineerfamily.net/` answers 401 (the "Sign in to continue" page),
   and `/privacy`, `/strelitzia/privacy`, `/healthz` and `/shared/site-header.js` answer 200.

#### How the workflow works

1. Resolves `ref` as a tag or branch commit on origin.
2. Force-resets the deployment state branch (`preprod` or `prod`) to that commit.
3. SSHs into the VPS as `deploy`, which runs `scripts/vps/engineerfamily-deploy`: fetch, `checkout -B <env> origin/<env>`,
   `reset --hard`, `site-version.sh` (as `deploy`), `up -d --build --remove-orphans`, then recreate nginx (its conf is a single-file bind mount).

---

### VPS Layout

| Path | Role |
|---|---|
| `~dev/src/{engineerfamily,Strelitzia,…}` | Development clones. All editing and commits happen here. |
| `/srv/engineerfamily-prod` | Prod checkout (branch `prod`, compose project `engineerfamily`). |
| `/srv/engineerfamily-preprod` | Preprod checkout (branch `preprod`, compose project `engineerfamily-preprod`, port 8080). |
| `/srv/Strelitzia-prod` | Prod dashboard build context, detached at its pinned tag (every prod deploy, `make strelitzia-deploy`). |
| `/srv/Strelitzia-preprod` | Preprod dashboard build context, at its pinned tag after `preprod-deploy`; moved to review-PR heads by Strelitzia's `scripts/agent/preprod.sh`. |
| `/srv/Wordle-prod` | Prod Wordle solver build context, detached at its pinned tag (every prod deploy, `make wordle-deploy [ref=<sha>]`). |
| `/srv/Wordle-preprod` | Preprod Wordle solver build context, at its pinned tag after `preprod-deploy` (`make preprod-wordle-deploy [ref=<sha>]`). |

`/srv` checkouts are `deploy:srv`, setgid and group-writable, and are never edited by hand. Compose project names are
pinned with `-p` (Makefile, deploy script) and `COMPOSE_PROJECT_NAME` in each checkout's `.env`, so a directory rename
never changes container or volume names.

Every prod and preprod `make` target acts on these `/srv` checkouts, so it can be run from the dev clone.
`make up` in `~/src/engineerfamily` restarts what is deployed in `/srv/engineerfamily-prod`, not your local edits.
Edits reach preprod with `make preprod-deploy` and prod with `make prod-release`, or for
Strelitzia with `make strelitzia-deploy`, and for the Wordle solver with `make wordle-deploy [ref=<sha>]`
(preprod: `make preprod-wordle-deploy [ref=<sha>]`). `prod-release`, `deploy-prod` and `preprod-deploy` build `wordle` too, so
`/srv/Wordle-prod` and `/srv/Wordle-preprod` must exist first. Use `make local-up` to run the dev tree.
