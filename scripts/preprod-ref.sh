#!/usr/bin/env bash
# The ref a preprod deploy checks out: every preprod deploy names a vX.Y.Z tag or a branch on origin, never a sha.
#
#   scripts/preprod-ref.sh <git dir> <ref>
#   scripts/preprod-ref.sh --check <ref>     # only the form (no fetch): exit 2 unless it could be a tag or a branch
#
# <ref>: vX.Y.Z, or a branch as `main`, `agent/x` or `origin/agent/x`. Fetches origin's tags and branches into <git dir>,
# then prints refs/tags/vX.Y.Z or refs/remotes/origin/<branch>. Anything else (a sha, HEAD~1, a branch origin doesn't
# have) exits 2 before the caller checks anything out. Used by preprod-deploy and preprod-wordle-deploy (Makefile).
set -euo pipefail

[ $# = 2 ] || { echo "usage: scripts/preprod-ref.sh <git dir|--check> <ref>" >&2; exit 2; }
dir=$1
ref=$2
refuse() { echo "preprod: $ref is not a vX.Y.Z tag or a branch on origin${1:+ ($1)}" >&2; exit 2; }

if [[ $ref =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    want=refs/tags/$ref
else
    branch=${ref#origin/}
    [[ ! $branch =~ ^[0-9a-f]{7,40}$ ]] || refuse "a sha"
    case $branch in HEAD|refs/*|"") refuse ;; esac
    git check-ref-format --branch "$branch" >/dev/null 2>&1 || refuse
    want=refs/remotes/origin/$branch
fi
[ "$dir" != --check ] || exit 0

git -C "$dir" fetch -q --prune --force --tags origin || { echo "preprod: git fetch in $dir failed" >&2; exit 1; }
git -C "$dir" rev-parse -q --verify "$want^{commit}" >/dev/null || refuse
echo "$want"
