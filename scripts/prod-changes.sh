#!/usr/bin/env bash
# What the next prod deploy would ship. Read-only: fetches, then prints git logs with PR links (from the subject's
# (#NN), else looked up with `gh api …/commits/<sha>/pulls` when gh is installed).
#
#   scripts/prod-changes.sh [--plan] [<target tag>]     (default target: the newest vX.Y.Z tag)
#
# engineerfamily: prod's tag → the target. Prod's tag is the newest full (promoted) GitHub release's tag, which is what
# `make prod-release` put on prod (a `make deploy-prod` rollback doesn't move it); without one, the tag origin/prod sits
# on, else the newest vX.Y.Z tag. Then `not in it:`, what origin/main has after the target.
# Each child in the target's components.toml: the tag (else the short sha) its prod checkout is on → the target's pin,
# logged from its dev clone, then `not pinned yet:` for its tags newer than the pin, naming the open pin-bump PR.
# Checkouts: $<NAME>_PROD_DIR (default /srv/<Repo>-prod) and $<NAME>_DEV_DIR (default ~/src/<Repo>), e.g.
# STRELITZIA_PROD_DIR and WORDLE_DEV_DIR; the preview skips a child whose checkout is missing, --plan fails.
#
# --plan prints only `name<TAB>prod_ref<TAB>target_ref<TAB>new|same|older` lines, engineerfamily first (scripts/prod-release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

gh=${GH:-gh}
site_repo=SiddharthEngineer/engineerfamily
plan=0
target=
for arg in "$@"; do
    case $arg in
        --plan) plan=1 ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "usage: scripts/prod-changes.sh [--plan] [<target tag>]" >&2; exit 2 ;;
        *) target=$arg ;;
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

pin_prs=
pin_prs_read=0
pin_pr() {  # pin_pr <name> <tag>: "#NN" of the open pin-bump PR titled "Pin <name> <tag>", if any
    if [ "$pin_prs_read" = 0 ]; then
        pin_prs_read=1
        if have_gh; then
            pin_prs=$("$gh" pr list --repo "$site_repo" --label pin-bump --state open --json number,title \
                --jq '.[] | "\(.number)\t\(.title)"' 2>/dev/null) || pin_prs=
        fi
    fi
    local n title
    while IFS=$'\t' read -r n title; do
        [ -n "$n" ] || continue
        shopt -s nocasematch
        if [[ $title == "Pin $1 $2" ]]; then shopt -u nocasematch; echo "#$n"; return; fi
        shopt -u nocasematch
    done <<<"$pin_prs"
}

# ─── engineerfamily ─────────────────────────────────────
git fetch -q --tags origin
if [ -z "$target" ]; then
    target=$(newest_tag .)
    [ -n "$target" ] || die "no vX.Y.Z tag found"
fi
[[ $target =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$target is not a vX.Y.Z tag"
git rev-parse -q --verify "refs/tags/$target" >/dev/null || die "no tag $target"

prod_tag=
if have_gh; then
    prod_tag=$("$gh" release list --repo "$site_repo" --exclude-pre-releases --exclude-drafts --limit 1 \
        --json tagName --jq '.[0].tagName // empty' 2>/dev/null) || true
fi
if [ -z "$prod_tag" ]; then
    # No full release found (gh missing or signed out, or none promoted yet): prod's own tag, else the newest tag.
    prod_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' origin/prod 2>/dev/null || newest_tag .)
    [ -z "$prod_tag" ] || echo "prod-changes: no full GitHub release found; using $prod_tag (from origin/prod or newest tag)" >&2
fi
[ -n "$prod_tag" ] || die "no prod tag (vX.Y.Z) found"

if [ "$prod_tag" = "$target" ]; then
    rel=same
elif [ "$(printf '%s\n' "$prod_tag" "$target" | sort -V | head -n 1)" = "$target" ]; then
    rel=older
else
    rel=new
fi
if [ "$plan" = 1 ]; then
    printf '%s\t%s\t%s\t%s\n' engineerfamily "$prod_tag" "$target" "$rel"
else
    echo "engineerfamily: $prod_tag → $target"
    case $rel in
        same) echo "  nothing new" ;;
        older) echo "  older than prod (a rollback is make deploy-prod ref=$target)" ;;
        new) log_with_links . "$site_repo" "$prod_tag..$target" ;;
    esac
    after=$(git log --oneline --first-parent "$target..origin/main")
    if [ -n "$after" ]; then
        echo "  not in it:"
        sed 's/^/    /' <<<"$after"
    fi
fi

# ─── children, at the target's pins ─────────────────────
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if ! git show "$target:components.toml" >"$tmp/components.toml" 2>/dev/null; then
    say
    say "No components.toml at $target: the deploy leaves the child checkouts as they are."
    exit 0
fi
pins=$(python3 scripts/components.py --file "$tmp/components.toml" list) || die "can't read $target:components.toml"

while IFS=$'\t' read -r name repo pin _service; do
    [ -n "$name" ] || continue
    say
    upper=$(tr '[:lower:]-' '[:upper:]_' <<<"$name")
    prod_var=${upper}_PROD_DIR
    dev_var=${upper}_DEV_DIR
    prod_dir=${!prod_var:-/srv/${repo##*/}-prod}
    dev_dir=${!dev_var:-$HOME/src/${repo##*/}}
    for pair in "$prod_dir:$prod_var" "$dev_dir:$dev_var"; do
        if ! is_checkout "${pair%%:*}"; then
            [ "$plan" = 0 ] || die "$name: ${pair%%:*} is not a git checkout (set ${pair##*:})"
            echo "$name: skipped, ${pair%%:*} is not a git checkout (set ${pair##*:})"
            continue 2
        fi
    done

    git -C "$dev_dir" fetch -q --force --tags origin
    git -C "$dev_dir" rev-parse -q --verify "refs/tags/$pin" >/dev/null || die "$name: no tag $pin in $dev_dir"
    prod_sha=$(git -C "$prod_dir" rev-parse HEAD) || die "can't read HEAD of $prod_dir"
    prod_ref=$(git -C "$prod_dir" describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null || echo "${prod_sha:0:12}")
    rel=$(relation "$dev_dir" "$prod_sha" "$pin")
    if [ "$plan" = 1 ]; then
        printf '%s\t%s\t%s\t%s\n' "$name" "$prod_ref" "$pin" "$rel"
        continue
    fi

    echo "$name: $prod_ref → $pin"
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
    newer=$(git -C "$dev_dir" tag -l 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V \
        | awk -v p="$pin" 'found { print } $0 == p { found = 1 }' || true)
    for t in $newer; do
        pr=$(pin_pr "$name" "$t")
        echo "  not pinned yet: $t${pr:+ (pin-bump PR $pr  https://github.com/$site_repo/pull/${pr#\#})}"
    done
done <<<"$pins"
