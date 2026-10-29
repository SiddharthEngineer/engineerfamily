#!/usr/bin/env bash
# Ship engineerfamily to prod with its components.toml pins, then promote every release it moved. The user's command
# (make prod-release [v=X.Y.Z] [dry=1]); agents never run it outside tests/prod-release-test.sh.
#
#   PROD='docker compose -p engineerfamily …' [GH=gh] scripts/prod-release.sh [--dry-run] [vX.Y.Z]
#
# 1. agent-runner versions sync for engineerfamily, strelitzia and wordle (exit 3 or 4: stop, see ROADMAP M4).
# 2. scripts/prod-changes.sh --plan [vX.Y.Z]. With no vX.Y.Z, each child without `hold` whose newest tag is newer than
#    main's pin moves (the target is main); else the newest vX.Y.Z tag, or the given one, with its pins as tagged.
#    Older than prod's tag: refused (roll back with make deploy-prod ref=…). Nothing moved: "Nothing to ship."
# 3. The prod-changes preview and one `Ship … to prod? [y/N]`.
# 3b. Pins moved: a release/pins-<UTC time> branch from origin/main with each move (components.py set), one
#    "Release pins: …" PR (label release-pins), gh pr checks --watch, gh pr merge --merge, then versions sync
#    engineerfamily tags the merge: that tag ships. Red CI or a failed merge stops here, naming the PR.
# 4. deploy.yml for the tag, and gh run watch. 5. Health checks (6 tries, $HEALTH_WAIT s apart, default 10).
# 6. Only then: versions promote engineerfamily <tag>, and versions promote <child> <pin> for each child whose pin moved.
# A failure at 4 or 5 promotes nothing. --dry-run syncs with --dry-run, shows the preview and the commands; no prompt,
# no branch.
set -euo pipefail
cd "$(dirname "$0")/.."

gh=${GH:-gh}
site_repo=SiddharthEngineer/engineerfamily
site=https://engineerfamily.net
health_wait=${HEALTH_WAIT:-10}
dry=0
tag=
for arg in "$@"; do
    case $arg in
        --dry-run) dry=1 ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "usage: scripts/prod-release.sh [--dry-run] [vX.Y.Z]" >&2; exit 2 ;;
        *) tag=v${arg#v} ;;
    esac
done
: "${PROD:?set PROD to the prod docker compose command (make prod-release passes it)}"

die() { echo "prod-release: $*" >&2; exit 1; }

# ─── 1. tags and pre-releases up to date ────────────────
sync_args=()
[ "$dry" = 0 ] || sync_args=(--dry-run)
for repo in engineerfamily strelitzia wordle; do
    rc=0
    agent-runner versions sync "$repo" ${sync_args[@]+"${sync_args[@]}"} || rc=$?
    case $rc in
        0) ;;
        3) die "$repo is waiting for a promote: tag the commit prod runs and run agent-runner versions promote $repo <tag> (ROADMAP M4)" ;;
        4) die "$repo is not set up for releases (no clone, runner.toml or [release]; ROADMAP M4)" ;;
        *) die "agent-runner versions sync $repo failed (exit $rc)" ;;
    esac
done

# ─── 2. what moves ──────────────────────────────────────
git fetch -q --tags origin
if [ -n "$tag" ]; then
    [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$tag is not a vX.Y.Z tag"
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "no tag $tag"
fi

asked=$tag    # the v= tag, if any; the plan below sets $tag to what ships (a tag, or main)
plan=$(bash scripts/prod-changes.sh --plan ${asked:+"$asked"}) || die "scripts/prod-changes.sh --plan $asked failed"
prod_tag=
site_rel=
moved=()        # children whose prod checkout moves: "name<TAB>pin"
pin_moves=()    # children whose pin moves in the release-pins PR: "name tag"
pins=()         # every child: "name pin", for the summary
changed=0
while IFS=$'\t' read -r name from to rel how why; do
    [ -n "$name" ] || continue
    if [ "$name" = engineerfamily ]; then
        prod_tag=$from
        tag=$to
        site_rel=$rel
        [ "$rel" != older ] || die "$tag is older than prod's $from; roll back with make deploy-prod ref=$tag (it promotes nothing)"
    else
        pins+=("$name $to")
        [ "$rel" != new ] || moved+=("$name"$'\t'"$to")
        [ "$how" != move ] || pin_moves+=("$name $to")
        [ "$how" != held ] || echo "held: $name ($why)"
    fi
    [ "$rel" = same ] || changed=1
done <<<"$plan"
[ -n "$prod_tag" ] || die "scripts/prod-changes.sh --plan printed no engineerfamily line"
if [ "$changed" = 0 ] && [ "${#pin_moves[@]}" = 0 ]; then
    echo "Nothing to ship: prod runs $tag and its pins."
    exit 0
fi
release_title="Release pins: $(printf '%s, ' "${pin_moves[@]}")"
release_title=${release_title%, }
release_branch=release/pins-$(date -u +%Y-%m-%d-%H%M%S)

# ─── 3. preview and the one question ────────────────────
bash scripts/prod-changes.sh ${asked:+"$asked"}
echo
promotes=()     # "repo tag": engineerfamily unless prod already runs its (promoted) tag, and each moved child
[ "$site_rel" = same ] || [ "$tag" = main ] || promotes+=("engineerfamily $tag")
for m in ${moved[@]+"${moved[@]}"}; do promotes+=("${m%%$'\t'*} ${m#*$'\t'}"); done
if [ "$dry" = 1 ]; then
    echo "Dry run. Would run:"
    if [ "$tag" = main ]; then
        echo "  git worktree add --detach <tmp> origin/main"
        for m in "${pin_moves[@]}"; do echo "  scripts/components.py --file <tmp>/components.toml set ${m% *} tag ${m#* }"; done
        echo "  git commit -am \"$release_title\"; git push origin HEAD:refs/heads/$release_branch"
        echo "  $gh pr create --repo $site_repo --base main --head $release_branch --label release-pins --title \"$release_title\""
        echo "  $gh pr checks <pr> --watch --fail-fast; $gh pr merge <pr> --merge --delete-branch"
        echo "  agent-runner versions sync engineerfamily   (tags the merge: <new tag>)"
        tag="<new tag>"
        promotes=("engineerfamily $tag" ${promotes[@]+"${promotes[@]}"})
    fi
    echo "  $gh workflow run deploy.yml --ref main -f environment=prod -f ref=$tag"
    echo "  $gh run watch <run> --exit-status"
    echo "  health checks: $site/healthz, strelitzia api/health (in its container), $site/strelitzia/privacy, $site/wordle/api/health"
    for p in ${promotes[@]+"${promotes[@]}"}; do echo "  agent-runner versions promote $p"; done
    exit 0
fi
if [ "$tag" = main ]; then printf 'Ship to prod (%s)? [y/N] ' "$release_title"; else printf 'Ship %s to prod? [y/N] ' "$tag"; fi
read -r answer || answer=
case $answer in y|Y|yes) ;; *) echo "Not shipped."; exit 1 ;; esac

# ─── 3b. the release-pins PR ────────────────────────────
if [ "$tag" = main ]; then
    wt=$(mktemp -d)
    trap 'git worktree remove --force "$wt/main" >/dev/null 2>&1 || true; rm -rf "$wt"' EXIT
    git worktree add -q --detach "$wt/main" origin/main
    for m in "${pin_moves[@]}"; do
        python3 scripts/components.py --file "$wt/main/components.toml" set "${m% *}" tag "${m#* }"
    done
    git -C "$wt/main" commit -qam "$release_title"
    echo "→ $release_title: pushing $release_branch"
    git -C "$wt/main" push -q origin "HEAD:refs/heads/$release_branch"
    "$gh" label create release-pins --repo "$site_repo" --color 0e8a16 \
        --description "make prod-release: moves components.toml pins" >/dev/null 2>&1 || true
    url=$("$gh" pr create --repo "$site_repo" --base main --head "$release_branch" --label release-pins \
        --title "$release_title" --body "Made by \`make prod-release\`: moves components.toml to the children's newest tags. Merging it tags the release that ships to prod.") \
        || die "gh pr create failed; $release_branch is pushed, nothing deployed"
    pr=${url##*/}
    echo "→ PR #$pr $url: waiting for CI"
    for _ in $(seq 30); do
        n=$("$gh" pr checks "$pr" --repo "$site_repo" --json name --jq length 2>/dev/null) || n=0
        [ "${n:-0}" -gt 0 ] && break
        sleep 2
    done
    "$gh" pr checks "$pr" --repo "$site_repo" --watch --fail-fast >/dev/null \
        || die "CI on release-pins PR #$pr is not green ($url); nothing deployed or promoted"
    "$gh" pr merge "$pr" --repo "$site_repo" --merge --delete-branch \
        || die "merging release-pins PR #$pr failed ($url); nothing deployed or promoted"
    agent-runner versions sync engineerfamily || die "PR #$pr merged, but agent-runner versions sync engineerfamily failed; nothing deployed. Run it, then make prod-release"
    git fetch -q --prune --tags origin
    tag=$(git tag --points-at origin/main | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1) || true
    [ -n "$tag" ] || die "PR #$pr merged, but origin/main has no vX.Y.Z tag; nothing deployed. Run agent-runner versions sync engineerfamily, then make prod-release"
    echo "→ PR #$pr merged as $tag"
    promotes=("engineerfamily $tag" ${promotes[@]+"${promotes[@]}"})
fi

# ─── 4. deploy ──────────────────────────────────────────
# The run is the first deploy.yml run newer than the trigger titled "Deploy <tag> to prod".
last=$("$gh" run list --workflow deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0')
echo "→ Triggering deploy of $tag to production..."
"$gh" workflow run deploy.yml --ref main -f environment=prod -f ref="$tag"
run=
for _ in $(seq 30); do
    run=$("$gh" run list --workflow deploy.yml --event workflow_dispatch --limit 5 --json databaseId,displayTitle \
        --jq "[.[] | select(.databaseId > $last and .displayTitle == \"Deploy $tag to prod\")] | last | .databaseId // empty")
    [ -n "$run" ] && break
    sleep 2
done
[ -n "$run" ] || die "no deploy.yml run started; nothing promoted"
"$gh" run watch "$run" --exit-status || die "deploy run $run failed; nothing promoted. Roll back: make deploy-prod ref=$prod_tag"

# ─── 5. health ──────────────────────────────────────────
http_200() { [ "$(curl -s -o /dev/null --max-time 20 -w '%{http_code}' "$1")" = 200 ]; }
json_ok() { curl -fsS --max-time 20 "$1" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*true'; }
strelitzia_api() { $PROD exec -T strelitzia curl -fsS http://127.0.0.1:8000/strelitzia/dashboard/api/health; }
check() {  # check <label> <command...>: up to 6 tries, $health_wait s apart
    local label=$1 try
    shift
    for ((try = 1; ; try++)); do
        if "$@" >/dev/null 2>&1; then
            echo "  ✓ $label"
            return 0
        fi
        if [ "$try" -ge 6 ]; then
            echo "  ✗ $label"
            return 1
        fi
        sleep "$health_wait"
    done
}
echo "→ Health checks"
check "$site/healthz" http_200 "$site/healthz" \
    && check "strelitzia api/health" strelitzia_api \
    && check "$site/strelitzia/privacy" http_200 "$site/strelitzia/privacy" \
    && check "$site/wordle/api/health" json_ok "$site/wordle/api/health" \
    || die "a health check failed; nothing promoted. Roll back: make deploy-prod ref=$prod_tag"

# ─── 6. promote what moved ──────────────────────────────
for i in "${!promotes[@]}"; do
    # shellcheck disable=SC2086  # "repo tag"
    agent-runner versions promote ${promotes[$i]} || {
        left=$(printf 'agent-runner versions promote %s; ' "${promotes[@]:$i}")
        die "$tag is on prod, but a promote failed. Still to run: ${left%; }"
    }
done
summary=$(for p in ${pins[@]+"${pins[@]}"}; do echo "$p"; done | paste -sd, - | sed 's/,/, /g')
echo "✓ $tag on prod${summary:+: $summary}"
