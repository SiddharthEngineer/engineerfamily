#!/usr/bin/env bash
# Where preprod puts each child repo. Checks nothing out: preprod-deploy resolves every ref first, so a refused one stops
# the deploy before anything moves.
#
#   scripts/preprod-pins.sh <components.toml> [--only <name>] [<name>=<tag|branch>…]
#
# Per component: the <name>= override, else its `preprod` key, else its newest vX.Y.Z tag on origin; each goes through
# scripts/preprod-ref.sh (exit 2 if refused). Prints name<TAB>checkout<TAB>ref to check out<TAB>asked<TAB>override|preprod
# key|newest. Checkouts: $STRELITZIA_PREPROD_DIR and $WORDLE_PREPROD_DIR (default /srv/<Repo>-preprod).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
usage() { echo "usage: scripts/preprod-pins.sh <components.toml> [--only <name>] [<name>=<tag|branch>…]" >&2; exit 2; }
[ $# -ge 1 ] || usage
toml=$1
shift
only=
declare -A over=()
while [ $# -gt 0 ]; do
    case $1 in
        --only) [ $# -ge 2 ] || usage; only=$2; shift 2 ;;
        *=*) [ -z "${1#*=}" ] || over[${1%%=*}]=${1#*=}; shift ;;
        *) usage ;;
    esac
done
comp() { python3 "$here/components.py" --file "$toml" "$@"; }

pins=$(comp list)
while IFS=$'\t' read -r name _repo _tag _service; do
    [ -n "$name" ] || continue
    [ -z "$only" ] || [ "$name" = "$only" ] || continue
    case $name in
        strelitzia) dir=${STRELITZIA_PREPROD_DIR:-/srv/Strelitzia-preprod} ;;
        wordle) dir=${WORDLE_PREPROD_DIR:-/srv/Wordle-preprod} ;;
        *) echo "unknown component '$name' in components.toml" >&2; exit 1 ;;
    esac
    if [ -n "${over[$name]:-}" ]; then
        want=${over[$name]} why=override
    elif want=$(comp get "$name" preprod 2>/dev/null); then
        why="preprod key"
    else
        want=$(comp newest "$name" --remote "$(git -C "$dir" remote get-url origin)") why=newest
    fi
    ref=$(bash "$here/preprod-ref.sh" "$dir" "$want")
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$dir" "$ref" "$want" "$why"
done <<<"$pins"
