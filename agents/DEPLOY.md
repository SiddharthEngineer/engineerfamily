# engineerfamily deploys

How engineerfamily releases and deploys work: the release model and tags, preprod and prod deploys, the deploy workflow, and
the VPS layout. Moved here from `README.md` on 2026-10-19 (ef-agents-layout). Prod deploys are always the user's call.
Before a prod deploy, `make prod-changes` shows what will ship.

### Release And Deployment Model

This repo uses four branch/tag concepts:

1. `main`
   - Ongoing development and PR merges.

2. `release-v<major>.<minor>`
   - Minor-line release branches (examples: `release-v1.0`, `release-v2.7`).
   - Created automatically when first tag for a minor line appears.

3. Release tags
   - Production tags: `v<major>.<minor>.<patch>` (example: `v1.2.3`).
   - Preprod tags: `v<major>.<minor>.<patch>-preprod` (example: `v1.2.3-preprod`).

4. Deployment state branches
   - `prod`: always points to what is deployed in production.
   - `preprod`: points to the last *tag* deploy to preprod. `make preprod-deploy` (below) doesn't move it, so
     `git -C /srv/engineerfamily-preprod log -1` is the source of truth for what preprod runs.

#### Tagging Rules

Use Make targets to create tags and keep release branches in sync:

```bash
make tag-preprod v=1.2.3
make tag-prod v=1.2.3
```

Enforced policy:

1. Tags for a minor line must be created from `main` or the matching `release-v<major>.<minor>` branch.
2. If `release-v<major>.<minor>` is ahead of `main`, tagging from `main` fails.
3. If tag is created from `main`, `main` is merged into the release branch.
4. If tag is created from release branch, release branch is aligned to latest tag in that minor line.

Validation/sync logic lives in:

- `scripts/release_branch_sync.sh`

### Deploying

#### Preprod Deploy (everyday: no tag)

Run on the VPS, from any directory (e.g. the dev clone):

```bash
make preprod-deploy                     # origin/main
make preprod-deploy ref=origin/my-branch # a pushed branch, before merging
make preprod-deploy ref=<sha|tag>
```

It checks that commit out in `/srv/engineerfamily-preprod`, rebuilds the stack (`up -d --build --remove-orphans`) and
reloads nginx. These are the same steps the deploy workflow runs, minus the tag and the GitHub round-trip. Push the commit first, because it
deploys what is on GitHub. Preprod tags (`make tag-preprod` + `make deploy-preprod`) are optional, for a release candidate you
want on record.

#### Prod Deploy (tag + workflow)

Prod deploys are always a tag, and two separate steps (tagging alone deploys nothing). Before a prod deploy, run
`make prod-changes`: it lists the engineerfamily commits since the last prod tag and the Strelitzia commits since what
`/srv/Strelitzia-prod` runs, each with its PR link, so you see exactly what will ship.

```bash
make tag-prod v=1.2.3          # validate-release-tagging, sync-release-branch, then tag v1.2.3 and push it
make deploy-prod ref=v1.2.3    # gh workflow run deploy.yml -f environment=prod -f ref=v1.2.3
```

Roll back with `make deploy-prod ref=<previous tag>`. The preprod equivalents are `make tag-preprod v=1.2.3` and
`make deploy-preprod ref=v1.2.3-preprod`.

Merging to `main` never ships prod: until the next tag + `deploy-prod`, prod keeps running the last tag. Check with
`git -C /srv/engineerfamily-prod describe --tags`, and compare with `git describe --tags origin/main`.
The `prod` branch in `/srv/engineerfamily-prod` (tracking `origin/prod`) belongs to the deploy script, which recreates it on
every deploy. Don't `git pull` there: it can only bring in what the last deploy pushed to `origin/prod`.
`tag-prod` pushes `release-v<major>.<minor>` without `-u`, so your `main` keeps tracking `origin/main`.

#### How the workflow works

1. Resolves `ref` as a tag or branch commit on origin.
2. Force-resets the deployment state branch (`preprod` or `prod`) to that commit.
3. SSHs into the VPS as `deploy`, which runs `scripts/vps/engineerfamily-deploy`: fetch, `checkout -B <env> origin/<env>`,
   `reset --hard`, `up -d --build --remove-orphans`, then recreate nginx (its conf is a single-file bind mount).

---

### VPS Layout

| Path | Role |
|---|---|
| `~dev/src/{engineerfamily,Strelitzia,…}` | Development clones. All editing and commits happen here. |
| `/srv/engineerfamily-prod` | Prod checkout (branch `prod`, compose project `engineerfamily`). |
| `/srv/engineerfamily-preprod` | Preprod checkout (branch `preprod`, compose project `engineerfamily-preprod`, port 8080). |
| `/srv/Strelitzia-prod` | Prod dashboard build context, detached at a trunk commit (`make strelitzia-deploy`). |
| `/srv/Strelitzia-preprod` | Preprod dashboard build context, moved to review-PR heads by Strelitzia's `scripts/agent/preprod.sh`. |

`/srv` checkouts are `deploy:srv`, setgid and group-writable, and are never edited by hand. Compose project names are
pinned with `-p` (Makefile, deploy script) and `COMPOSE_PROJECT_NAME` in each checkout's `.env`, so a directory rename
never changes container or volume names.

Every prod and preprod `make` target acts on these `/srv` checkouts, so it can be run from the dev clone.
`make up` in `~/src/engineerfamily` restarts what is deployed in `/srv/engineerfamily-prod`, not your local edits.
Edits reach preprod with `make preprod-deploy` and prod with `make tag-prod` + `make deploy-prod`, or for
Strelitzia with `make strelitzia-deploy`. Use `make local-up` to run the dev tree.
