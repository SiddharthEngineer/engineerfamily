#!/usr/bin/env bash
# What the next prod deploy would ship. Read-only: fetches, then prints three git logs with PR links
# (from the subject's (#NN), else looked up with `gh api …/commits/<sha>/pulls` when gh is installed).
#
#   scripts/prod-changes.sh [strelitzia-prod-dir] [wordle-prod-dir]
#   (defaults /srv/Strelitzia-prod, /srv/Wordle-prod; make prod-changes passes STRELITZIA_PROD_DIR and WORDLE_PROD_DIR)
#
# engineerfamily: the newest prod tag (vX.Y.Z, not -preprod) .. origin/main. Prod tags may not be ancestors of
# origin/main (release-branch sync), so the tag is found by version sort, not `git describe`.
# Strelitzia: the commit /srv/Strelitzia-prod is on .. origin/trunk, from the dev clone $STRELITZIA_DEV_DIR (~/src/Strelitzia).
# Wordle: the commit /srv/Wordle-prod is on .. origin/main, from $WORDLE_DEV_DIR (~/src/Wordle); skipped with a note
# when either checkout is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

prod_dir=${1:-/srv/Strelitzia-prod}
dev_dir=${STRELITZIA_DEV_DIR:-$HOME/src/Strelitzia}
wordle_prod_dir=${2:-/srv/Wordle-prod}
wordle_dev_dir=${WORDLE_DEV_DIR:-$HOME/src/Wordle}

die() { echo "prod-changes: $*" >&2; exit 1; }

pr_of() {  # pr_of <github repo> <sha>: the PR that brought a commit in (merge-commit and rebase merges carry no "(#NN)")
    command -v gh >/dev/null || return 0
    gh api "repos/$1/commits/$2/pulls" --jq '.[0].number // empty' 2>/dev/null || true
}

log_with_links() {  # log_with_links <git dir> <github repo> <range>
    local out sha subject n
    out=$(git -C "$1" log --oneline --no-merges "$3")
    if [ -z "$out" ]; then
        echo "  nothing new"
        return
    fi
    while read -r sha subject; do
        if [[ $subject =~ \(#([0-9]+)\) ]] || [[ $subject =~ Merge\ pull\ request\ #([0-9]+) ]]; then
            n=${BASH_REMATCH[1]}
        else
            n=$(pr_of "$2" "$sha")
        fi
        echo "  $sha $subject${n:+  https://github.com/$2/pull/$n}"
    done <<<"$out"
}

is_checkout() { [ -d "$1/.git" ] || [ -f "$1/.git" ]; }

[ -d "$prod_dir/.git" ] || [ -f "$prod_dir/.git" ] || die "$prod_dir is not a git checkout (set STRELITZIA_PROD_DIR)"
[ -d "$dev_dir/.git" ] || die "$dev_dir is not a git checkout (set STRELITZIA_DEV_DIR)"

git fetch -q --tags origin
tag=$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -v -- '-preprod' | head -n 1) || true
[ -n "$tag" ] || die "no prod tag (vX.Y.Z) found"
echo "engineerfamily: $tag..origin/main"
log_with_links . SiddharthEngineer/engineerfamily "$tag..origin/main"

echo
git -C "$dev_dir" fetch -q origin
prod_sha=$(git -C "$prod_dir" rev-parse HEAD) || die "can't read HEAD of $prod_dir"
echo "Strelitzia: ${prod_sha:0:12}..origin/trunk"
log_with_links "$dev_dir" SiddharthEngineer/Strelitzia "$prod_sha..origin/trunk"

echo
if ! is_checkout "$wordle_prod_dir"; then
    echo "Wordle: skipped, $wordle_prod_dir is not a git checkout (set WORDLE_PROD_DIR)"
elif ! is_checkout "$wordle_dev_dir"; then
    echo "Wordle: skipped, $wordle_dev_dir is not a git checkout (set WORDLE_DEV_DIR)"
else
    git -C "$wordle_dev_dir" fetch -q origin
    wordle_sha=$(git -C "$wordle_prod_dir" rev-parse HEAD) || die "can't read HEAD of $wordle_prod_dir"
    echo "Wordle: ${wordle_sha:0:12}..origin/main"
    log_with_links "$wordle_dev_dir" SiddharthEngineer/Wordle "$wordle_sha..origin/main"
fi
