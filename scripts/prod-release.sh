#!/usr/bin/env bash
# Ship one engineerfamily tag to prod with its components.toml pins, then promote every release it moved. The user's
# command (make prod-release [v=X.Y.Z] [dry=1]); agents never run it outside tests/prod-release-test.sh.
#
#   PROD='docker compose -p engineerfamily …' [GH=gh] scripts/prod-release.sh [--dry-run] [vX.Y.Z]
#
# 1. agent-runner versions sync for engineerfamily, strelitzia and wordle (exit 3 or 4: stop, see ROADMAP M4).
# 2. The tag (default: the newest vX.Y.Z); scripts/prod-changes.sh --plan. Older than prod's tag: refused (roll back
#    with make deploy-prod ref=…). Nothing moved: "Nothing to ship."
# 3. The prod-changes preview and one `Ship <tag> to prod? [y/N]`.
# 4. deploy.yml for the tag, and gh run watch. 5. Health checks (6 tries, $HEALTH_WAIT s apart, default 10).
# 6. Only then: versions promote engineerfamily <tag>, and versions promote <child> <pin> for each child whose pin moved.
# A failure at 4 or 5 promotes nothing. --dry-run syncs with --dry-run, shows the preview and the commands; no prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

gh=${GH:-gh}
site=https://engineerfamily.net
health_wait=${HEALTH_WAIT:-10}
dry=0
tag=
for arg in "$@"; do
    case $arg in
        --dry-run) dry=1 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
if [ -z "$tag" ]; then
    tag=$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1) || true
    [ -n "$tag" ] || die "no vX.Y.Z tag found"
fi
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$tag is not a vX.Y.Z tag"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "no tag $tag"

plan=$(bash scripts/prod-changes.sh --plan "$tag") || die "scripts/prod-changes.sh --plan $tag failed"
prod_tag=
moved=()        # children whose pin is new: "name<TAB>pin"
pins=()         # every child: "name pin", for the summary
changed=0
while IFS=$'\t' read -r name from to rel; do
    [ -n "$name" ] || continue
    if [ "$name" = engineerfamily ]; then
        prod_tag=$from
        [ "$rel" != older ] || die "$tag is older than prod's $from; roll back with make deploy-prod ref=$tag (it promotes nothing)"
    else
        pins+=("$name $to")
        [ "$rel" != new ] || moved+=("$name"$'\t'"$to")
    fi
    [ "$rel" = same ] || changed=1
done <<<"$plan"
[ -n "$prod_tag" ] || die "scripts/prod-changes.sh --plan printed no engineerfamily line"
if [ "$changed" = 0 ]; then
    echo "Nothing to ship: prod runs $tag and its pins."
    exit 0
fi

# ─── 3. preview and the one question ────────────────────
bash scripts/prod-changes.sh "$tag"
echo
promotes=("engineerfamily $tag")
for m in ${moved[@]+"${moved[@]}"}; do promotes+=("${m%%$'\t'*} ${m#*$'\t'}"); done
if [ "$dry" = 1 ]; then
    echo "Dry run. Would run:"
    echo "  $gh workflow run deploy.yml --ref main -f environment=prod -f ref=$tag"
    echo "  $gh run watch <run> --exit-status"
    echo "  health checks: $site/healthz, strelitzia api/health (in its container), $site/strelitzia/privacy, $site/wordle/api/health"
    for p in "${promotes[@]}"; do echo "  agent-runner versions promote $p"; done
    exit 0
fi
printf 'Ship %s to prod? [y/N] ' "$tag"
read -r answer || answer=
case $answer in y|Y|yes) ;; *) echo "Not shipped."; exit 1 ;; esac

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
for p in "${promotes[@]}"; do
    # shellcheck disable=SC2086  # "name tag"
    agent-runner versions promote $p
done
summary=$(for p in ${pins[@]+"${pins[@]}"}; do echo "$p"; done | paste -sd, - | sed 's/,/, /g')
echo "✓ $tag on prod${summary:+: $summary}"
