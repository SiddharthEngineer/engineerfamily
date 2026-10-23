#!/usr/bin/env bash
# Writes services/shared/version.json ({"label", "url"}) for the header's version text (<ef-profile> in
# services/shared/site-header.js), from the checkout's HEAD. Run after every deploy's checkout: preprod-deploy (Makefile)
# and scripts/vps/engineerfamily-deploy (as `deploy`). The file is gitignored; nginx serves it from /shared/.
#
#   scripts/site-version.sh <prod|preprod> [checkout dir, default: this repo]
#
# prod:    exact vX.Y.Z tag → "vX.Y", linking to that tag's release; no tag → the short sha.
# preprod: exact vX.Y.Z tag → it; else a remote branch at HEAD other than main/preprod/prod → its name, linking to its
#          PRs; else the nearest tag on main's first-parent line → "vX.Y.Z+N"; else the short sha.
set -euo pipefail

env=${1:-}
dir=${2:-$(cd "$(dirname "$0")/.." && pwd)}
case "$env" in prod|preprod) ;; *) echo "usage: site-version.sh <prod|preprod> [dir]" >&2; exit 2 ;; esac
dir=$(cd "$dir" && pwd)

REPO_URL=https://github.com/SiddharthEngineer/engineerfamily
git() { command git -c safe.directory="$dir" -C "$dir" "$@"; }
json_str() { local s=${1//\\/\\\\}; printf '"%s"' "${s//\"/\\\"}"; }

sha=$(git rev-parse HEAD)
short=$(git rev-parse --short HEAD)
label=$short
url="$REPO_URL/commit/$sha"

exact=$(git tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1) || true
if [ -n "$exact" ]; then
    url="$REPO_URL/releases/tag/$exact"
    if [ "$env" = prod ]; then label=${exact%.*}; else label=$exact; fi
elif [ "$env" = preprod ]; then
    branch=$(git branch -r --points-at HEAD --format='%(refname:lstrip=3)' \
        | grep -vxE 'HEAD|main|preprod|prod' | head -n 1) || true
    if [ -n "$branch" ]; then
        label=$branch
        url="$REPO_URL/pulls?q=is:pr+head:$branch"
    else
        near=$(git describe --tags --first-parent --abbrev=0 --match 'v[0-9]*' --exclude '*-*' HEAD 2>/dev/null) || true
        if [[ $near =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            label="$near+$(git rev-list --count --first-parent "$near..HEAD")"
            url="$REPO_URL/compare/$near...$sha"
        fi
    fi
fi

out="$dir/services/shared/version.json"
tmp=$(mktemp "$out.XXXXXX")
printf '{"label": %s, "url": %s}\n' "$(json_str "$label")" "$(json_str "$url")" >"$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$out"
echo "version.json: $label"
