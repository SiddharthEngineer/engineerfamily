#!/usr/bin/env bash
# What the next prod release would ship. Read-only: fetches, then prints git logs with PR links (from the subject's
# (#NN), else looked up with `gh api …/commits/<sha>/pulls` when gh is installed).
#
#   scripts/prod-changes.sh [--plan] [<target tag>]
#
# With no target, the next release: each child in origin/main's components.toml whose newest vX.Y.Z tag is newer than
# its pin (and that has no `hold`) moves to that tag. If one does, the target is main, whose release-pins PR gets the
# next tag (make prod-release makes it); else the target is the newest vX.Y.Z tag. With a target tag, its pins as tagged.
# engineerfamily: prod's tag → the target. Prod's tag is the newest full (promoted) GitHub release's tag, which is what
# `make prod-release` put on prod (a `make deploy-prod` rollback doesn't move it); without one, the tag origin/prod sits
# on, else the newest vX.Y.Z tag. Then `not in it:`, what origin/main has after a target tag.
# Each child: the tag (else the short sha) its prod checkout is on → the target's pin or the newest tag, logged from its
# dev clone; `held: <reason>` for a child with `hold`. Checkouts: $<NAME>_PROD_DIR (default /srv/<Repo>-prod) and
# $<NAME>_DEV_DIR (default ~/src/<Repo>), e.g. STRELITZIA_PROD_DIR and WORDLE_DEV_DIR; the preview skips a child whose
# checkout is missing, --plan fails.
#
# --plan prints only tab-separated lines, engineerfamily first (scripts/prod-release.sh reads them):
#   engineerfamily  prod_tag  target (vX.Y.Z or main)  new|same|older
#   <child>         prod_ref  target_ref               new|same|older  move|pin|held  [hold reason]
set -euo pipefail
cd "$(dirname "$0")/.."

gh=${GH:-gh}
site_repo=SiddharthEngineer/engineerfamily
plan=0
target=
for arg in "$@"; do
    case $arg in
        --plan) plan=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "usage: scripts/prod-changes.sh [--plan] [<target tag>]" >&2; exit 2 ;;
        *) [[ $arg =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "prod-changes: $arg is not a vX.Y.Z tag" >&2; exit 2; }; target=$arg ;;
    esac
done

die() { echo "prod-changes: $*" >&2; exit 1; }
say() { [ "$plan" = 1 ] || echo "$@"; }
have_gh() { command -v "$gh" >/dev/null; }
is_checkout() { [ -d "$1/.git" ] || [ -f "$1/.git" ]; }
newest_tag() { git -C "$1" tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true; }

pr_of() {  # pr_of <github repo> <sha>: the PR that brought a commit in (merge-commit and rebase merges carry no "(#NN)")
    have_gh || return 0
    "$gh" api "repos/$1/commits/$2/pulls" --jq '.[0].number // empty' 2>/dev/null || true
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

relation() {  # relation <git dir> <prod commit> <target commit>: new, same, or older (the target is behind prod)
    local a b
    a=$(git -C "$1" rev-parse -q --verify "$2^{commit}") || { echo new; return; }
    b=$(git -C "$1" rev-parse "$3^{commit}")
    if [ "$a" = "$b" ]; then echo same
    elif git -C "$1" merge-base --is-ancestor "$b" "$a"; then echo older
    else echo new
    fi
}

newer() {  # newer <a> <b>: a is a later vX.Y.Z than b
    [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}
dirs_of() {  # dirs_of <name> <github repo>: sets prod_dir, dev_dir and their variable names
    local upper
    upper=$(tr '[:lower:]-' '[:upper:]_' <<<"$1")
    prod_var=${upper}_PROD_DIR
    dev_var=${upper}_DEV_DIR
    prod_dir=${!prod_var:-/srv/${2##*/}-prod}
    dev_dir=${!dev_var:-$HOME/src/${2##*/}}
}

# ─── the next release: which children move ──────────────
git fetch -q --tags origin
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
comp() { python3 scripts/components.py "$@"; }
declare -A how=() reason=() to=()
explicit=$target
if git show origin/main:components.toml >"$tmp/main.toml" 2>/dev/null; then
    main_pins=$(comp --file "$tmp/main.toml" list) || die "can't read origin/main:components.toml"
    while IFS=$'\t' read -r name repo pin _service; do
        [ -n "$name" ] || continue
        if r=$(comp --file "$tmp/main.toml" get "$name" hold 2>/dev/null); then
            how[$name]=held
            reason[$name]=$r
            continue
        fi
        [ -z "$explicit" ] || continue
        dirs_of "$name" "$repo"
        url=
        ! is_checkout "$dev_dir" || url=$(git -C "$dev_dir" remote get-url origin)
        newest=$(comp --file "$tmp/main.toml" newest "$name" ${url:+--remote "$url"}) || die "$name: can't read its newest tag"
        if newer "$newest" "$pin"; then
            how[$name]=move
            to[$name]=$newest
        fi
    done <<<"$main_pins"
    [ -n "$explicit" ] || [ "${#to[@]}" = 0 ] || target=main
fi

# ─── engineerfamily ─────────────────────────────────────
if [ -z "$target" ]; then
    target=$(newest_tag .)
    [ -n "$target" ] || die "no vX.Y.Z tag found"
fi
if [ "$target" = main ]; then
    target_ref=origin/main
else
    [[ $target =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$target is not a vX.Y.Z tag"
    git rev-parse -q --verify "refs/tags/$target" >/dev/null || die "no tag $target"
    target_ref=$target
fi

prod_tag=
if have_gh; then
    # --plan decides what prod-release ships, so it doesn't guess when GitHub can't be asked.
    prod_tag=$("$gh" release list --repo "$site_repo" --exclude-pre-releases --exclude-drafts --limit 1 \
        --json tagName --jq '.[0].tagName // empty' 2>/dev/null) \
        || { [ "$plan" = 0 ] || die "gh release list failed: can't tell which tag prod runs"; prod_tag=; }
elif [ "$plan" = 1 ]; then
    die "gh not found: can't tell which tag prod runs"
fi
if [ -z "$prod_tag" ]; then
    # No full release found (gh missing or signed out, or none promoted yet): prod's own tag, else the newest tag.
    prod_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' origin/prod 2>/dev/null || newest_tag .)
    [ -z "$prod_tag" ] || echo "prod-changes: no full GitHub release found; using $prod_tag (from origin/prod or newest tag)" >&2
fi
[ -n "$prod_tag" ] || die "no prod tag (vX.Y.Z) found"

if [ "$target" = main ]; then
    rel=$(relation . "$prod_tag" origin/main)
elif [ "$prod_tag" = "$target" ]; then
    rel=same
elif [ "$(printf '%s\n' "$prod_tag" "$target" | sort -V | head -n 1)" = "$target" ]; then
    rel=older
else
    rel=new
fi
if [ "$plan" = 1 ]; then
    printf '%s\t%s\t%s\t%s\n' engineerfamily "$prod_tag" "$target" "$rel"
else
    if [ "$target" = main ]; then
        echo "engineerfamily: $prod_tag → main (its release-pins merge gets the next tag)"
    else
        echo "engineerfamily: $prod_tag → $target"
    fi
    case $rel in
        same) echo "  nothing new" ;;
        older) echo "  older than prod (a rollback is make deploy-prod ref=$target)" ;;
        new) log_with_links . "$site_repo" "$prod_tag..$target_ref" ;;
    esac
    after=$(git log --oneline --first-parent "$target_ref..origin/main")
    if [ -n "$after" ]; then
        echo "  not in it:"
        sed 's/^/    /' <<<"$after"
    fi
fi

# ─── children, at the target's pins or their newest tag ─
if ! git show "$target_ref:components.toml" >"$tmp/components.toml" 2>/dev/null; then
    say
    say "No components.toml at $target: the deploy leaves the child checkouts as they are."
    exit 0
fi
pins=$(comp --file "$tmp/components.toml" list) || die "can't read $target:components.toml"

while IFS=$'\t' read -r name repo pin _service; do
    [ -n "$name" ] || continue
    say
    dirs_of "$name" "$repo"
    for pair in "$prod_dir:$prod_var" "$dev_dir:$dev_var"; do
        if ! is_checkout "${pair%%:*}"; then
            [ "$plan" = 0 ] || die "$name: ${pair%%:*} is not a git checkout (set ${pair##*:})"
            echo "$name: skipped, ${pair%%:*} is not a git checkout (set ${pair##*:})"
            continue 2
        fi
    done

    h=${how[$name]:-pin}
    [ "$h" != move ] || pin=${to[$name]}
    git -C "$dev_dir" fetch -q --force --tags origin
    git -C "$dev_dir" rev-parse -q --verify "refs/tags/$pin" >/dev/null || die "$name: no tag $pin in $dev_dir"
    prod_sha=$(git -C "$prod_dir" rev-parse HEAD) || die "can't read HEAD of $prod_dir"
    prod_ref=$(git -C "$prod_dir" describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null || echo "${prod_sha:0:12}")
    rel=$(relation "$dev_dir" "$prod_sha" "$pin")
    if [ "$plan" = 1 ]; then
        printf '%s\t%s\t%s\t%s\t%s%s\n' "$name" "$prod_ref" "$pin" "$rel" "$h" "${reason[$name]:+$'\t'${reason[$name]}}"
        continue
    fi

    case $h in
        move) echo "$name: $prod_ref → $pin (newest tag, pinned by this release)" ;;
        *) echo "$name: $prod_ref → $pin" ;;
    esac
    [ "$h" != held ] || echo "  held: ${reason[$name]}"
    case $rel in
        same) echo "  nothing new" ;;
        older) echo "  older than prod: this deploy moves $name back to $pin" ;;
        new)
            if git -C "$dev_dir" cat-file -e "$prod_sha^{commit}" 2>/dev/null; then
                log_with_links "$dev_dir" "$repo" "$prod_sha..$pin"
            else
                echo "  (prod's commit ${prod_sha:0:12} isn't in $dev_dir, so no log)"
            fi ;;
    esac
    if [ "$h" = pin ]; then
        newest=$(newest_tag "$dev_dir")
        ! newer "$newest" "$pin" || echo "  newer tag, not in $target: $newest (make prod-release without v= pins it)"
    fi
done <<<"$pins"
