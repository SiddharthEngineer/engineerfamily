#!/usr/bin/env bash
# scripts/preprod-ref.sh and `make preprod-deploy` against temp repos: an engineerfamily origin with a components.toml,
# Strelitzia and Wordle origins with tags and branches, and "preprod" checkouts of each. PREPROD=true stands in for
# docker compose. Never touches /srv. One `ok` line per case; exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."
src=$PWD
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL $*" >&2; exit 1; }

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$tmp/gitconfig
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main
git config --global advice.detachedHead false
git config --global commit.gpgsign false
git config --global tag.gpgsign false

commit() {  # commit <dir> <message> [tag]
    echo "$2" >>"$1/log.txt"
    git -C "$1" add -A
    git -C "$1" commit -qm "$2"
    [ -z "${3:-}" ] || git -C "$1" tag -a "$3" -m "$3"
}
pins() {  # pins <dir> [extra strelitzia line]
    printf '[strelitzia]\nrepo = "SiddharthEngineer/Strelitzia"\ntag = "v1.0.0"\nservice = "strelitzia"\n%s\n\n' "${2:-}" >"$1/components.toml"
    printf '[wordle]\nrepo = "SiddharthEngineer/Wordle"\ntag = "v1.0.0"\nservice = "wordle"\n' >>"$1/components.toml"
}

# Children: tags v1.0.0, v1.2.0, v1.10.0 (newest by version, not by name) and a branch agent/x.
for child in Strelitzia Wordle; do
    w=$tmp/work-$child
    git init -q "$w"
    commit "$w" one v1.0.0
    commit "$w" two v1.10.0
    commit "$w" three v1.2.0
    git -C "$w" checkout -q -b agent/x
    commit "$w" branch
    git -C "$w" checkout -q main
    git init -q --bare "$tmp/$child.git"
    git -C "$w" remote add origin "$tmp/$child.git"
    git -C "$w" push -q --tags origin main agent/x
    git clone -q "$tmp/$child.git" "$tmp/$child-preprod"
done
# engineerfamily: main pins v1.0.0 everywhere; branch agent/x freezes strelitzia with a preprod key.
w=$tmp/work-ef
git init -q "$w"
pins "$w"; commit "$w" "site one" v1.0.0
git -C "$w" checkout -q -b agent/x
pins "$w" 'preprod = "v1.2.0"'; commit "$w" "freeze strelitzia"
git -C "$w" checkout -q main
git init -q --bare "$tmp/ef.git"
git -C "$w" remote add origin "$tmp/ef.git"
git -C "$w" push -q --tags origin main agent/x
git clone -q "$tmp/ef.git" "$tmp/ef-preprod"
sha=$(git -C "$tmp/ef-preprod" rev-parse HEAD)

at() { git -C "$1" rev-parse HEAD; }
tag_sha() { git -C "$1" rev-parse "$2^{commit}"; }
deploy() {  # deploy <make args...>: output in $out, exit code in $rc
    rc=0
    out=$(make -s -C "$src" preprod-deploy PREPROD=true PREPROD_DIR="$tmp/ef-preprod" \
        STRELITZIA_PREPROD_DIR="$tmp/Strelitzia-preprod" WORDLE_PREPROD_DIR="$tmp/Wordle-preprod" "$@" 2>&1) || rc=$?
}
expect() {  # expect <case> <condition text> <test...>
    local name=$1 what=$2; shift 2
    "$@" || fail "$name: $what
--- output (exit $rc) ---
$out"
}
has() { grep -qF -- "$1" <<<"$out"; }

# preprod-ref.sh: tags and branches resolve; a sha, HEAD~1 and a missing branch exit 2.
d=$tmp/Strelitzia-preprod
[ "$(bash scripts/preprod-ref.sh "$d" v1.2.0)" = refs/tags/v1.2.0 ] || fail "ref: v1.2.0"
[ "$(bash scripts/preprod-ref.sh "$d" main)" = refs/remotes/origin/main ] || fail "ref: main"
[ "$(bash scripts/preprod-ref.sh "$d" origin/agent/x)" = refs/remotes/origin/agent/x ] || fail "ref: origin/agent/x"
[ "$(bash scripts/preprod-ref.sh "$d" agent/x)" = refs/remotes/origin/agent/x ] || fail "ref: agent/x"
for bad in "$(at "$d")" HEAD~1 HEAD no-such-branch v9.9.9 "v1.2"; do
    rc=0; out=$(bash scripts/preprod-ref.sh "$d" "$bad" 2>&1) || rc=$?
    expect "ref $bad" "exit 2" [ "$rc" = 2 ]
    expect "ref $bad" "message" has "preprod: $bad is not a vX.Y.Z tag or a branch on origin"
done
echo "ok  preprod-ref.sh: tags and branches resolve; sha, HEAD~1, HEAD and missing refs refused"

# No ref, a sha or HEAD~1: refused before anything is checked out.
before=$(at "$tmp/Strelitzia-preprod")
deploy
expect "no ref" "exit non-zero" [ "$rc" != 0 ]
expect "no ref" "message" has "preprod-deploy needs ref=<tag|branch> (e.g. ref=main)"
for bad in "$sha" HEAD~1 no-such-branch; do
    deploy ref="$bad"
    expect "ref=$bad" "exit non-zero" [ "$rc" != 0 ]
    expect "ref=$bad" "message" has "preprod: $bad is not a vX.Y.Z tag or a branch on origin"
done
deploy ref=main strelitzia=HEAD~1
expect "strelitzia=HEAD~1" "exit non-zero" [ "$rc" != 0 ]
expect "strelitzia=HEAD~1" "message" has "preprod: HEAD~1 is not a vX.Y.Z tag or a branch on origin"
expect "refusals" "no checkout" [ "$(at "$tmp/ef-preprod")$(at "$tmp/Strelitzia-preprod")" = "$sha$before" ]
expect "refusals" "still on main" [ "$(git -C "$tmp/ef-preprod" branch --show-current)" = main ]
echo "ok  preprod-deploy: no ref, a sha, HEAD~1, a missing branch and a bad override refused before any checkout"

# ref=main: both children float to their newest tag, v1.10.0.
deploy ref=main
expect main "exit 0" [ "$rc" = 0 ]
expect main "strelitzia newest" has "→ strelitzia at v1.10.0 (newest)"
expect main "wordle newest" has "→ wordle at v1.10.0 (newest)"
expect main "checked out" [ "$(at "$tmp/Strelitzia-preprod")" = "$(tag_sha "$tmp/Strelitzia-preprod" v1.10.0)" ]
expect main "on the preprod branch" [ "$(git -C "$tmp/ef-preprod" branch --show-current)" = preprod ]
echo "ok  ref=main: children float to their newest tag"

# ref=origin/agent/x has the preprod key (strelitzia v1.2.0); an override beats it; wordle=<branch> works.
deploy ref=origin/agent/x wordle=agent/x
expect key "exit 0" [ "$rc" = 0 ]
expect key "preprod key" has "→ strelitzia at v1.2.0 (preprod key)"
expect key "wordle branch" has "→ wordle at agent/x (override)"
expect key "wordle checked out" [ "$(at "$tmp/Wordle-preprod")" = "$(tag_sha "$tmp/Wordle-preprod" origin/agent/x)" ]
mkdir -p "$tmp/ef-preprod/services/shared"
out=$(bash scripts/site-version.sh preprod "$tmp/ef-preprod")
expect key "header labels the branch" has "version.json: agent/x"
deploy ref=agent/x strelitzia=v1.0.0
expect override "exit 0" [ "$rc" = 0 ]
expect override "override beats the key" has "→ strelitzia at v1.0.0 (override)"
expect override "checked out" [ "$(at "$tmp/Strelitzia-preprod")" = "$(tag_sha "$tmp/Strelitzia-preprod" v1.0.0)" ]
echo "ok  the preprod key beats newest; an override beats the key"

# ref=v1.0.0 (a tag) deploys that tag.
deploy ref=v1.0.0
expect tag "exit 0" [ "$rc" = 0 ]
expect tag "at the tag" [ "$(at "$tmp/ef-preprod")" = "$(tag_sha "$tmp/ef-preprod" v1.0.0)" ]
echo "ok  ref=v1.0.0 deploys the tag"
