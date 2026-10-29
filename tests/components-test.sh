#!/usr/bin/env bash
# scripts/components.py against temp files: a good file passes and lists its components; each kind of problem fails
# with the problem named. Prints one `ok` line per case and exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
good='[strelitzia]
repo = "SiddharthEngineer/Strelitzia"
tag = "v1.0.0"
service = "strelitzia"

[wordle]
repo = "SiddharthEngineer/Wordle"
tag = "v1.0.0"
service = "wordle"
hold = "waiting on a fix"'

run() { python3 scripts/components.py --file "$tmp/c.toml" "$@"; }
fail() { echo "FAIL $*" >&2; exit 1; }

printf '%s\n' "$good" > "$tmp/c.toml"
run check >/dev/null || fail "good file: check exited non-zero"
[ "$(run list | wc -l)" -eq 2 ] || fail "good file: list should print 2 lines"
[ "$(run get wordle tag)" = v1.0.0 ] || fail "good file: get wordle tag"
echo "ok  good file"

bad() {  # bad <case> <expected text> <sed expression applied to the good file>
    printf '%s\n' "$good" | sed "$3" > "$tmp/c.toml"
    local out
    if out=$(run check); then fail "$1: check exited 0"; fi
    grep -q "$2" <<< "$out" || fail "$1: expected '$2', got: $out"
    echo "ok  $1"
}
bad "bad tag"     "bad tag 'v1.0'"        's/tag = "v1.0.0"/tag = "v1.0"/'
bad "missing key" "missing 'service'"     '/service = "wordle"/d'
bad "unknown key" "unknown key 'branch'"  's/^hold = .*/branch = "main"/'
bad "bad name"    "Wordle: bad name"      's/^\[wordle\]/[Wordle]/'

# set rewrites only that component's tag line; newest picks the highest vX.Y.Z on a remote.
printf '%s\n' "$good" | sed 's/^service = "wordle"/&  # keep me/' > "$tmp/c.toml"
cp "$tmp/c.toml" "$tmp/before.toml"
run set wordle tag v1.4.0
[ "$(run get wordle tag)" = v1.4.0 ] && [ "$(run get strelitzia tag)" = v1.0.0 ] || fail "set: wrong tag moved"
[ "$(diff "$tmp/before.toml" "$tmp/c.toml" | grep -c '^[<>]')" = 2 ] || fail "set: more than the tag line changed"
grep -q '# keep me' "$tmp/c.toml" || fail "set: comment lost"
if run set wordle tag 1.4 2>/dev/null; then fail "set: accepted a bad tag"; fi
echo "ok  set wordle tag"
git init -q "$tmp/r"
git -C "$tmp/r" -c user.name=t -c user.email=t@e commit -q --allow-empty -m one
for t in v1.2.0 v1.10.0 v1.9.9 v2.0.0-rc1 latest; do git -C "$tmp/r" tag "$t"; done
[ "$(run newest wordle --remote "$tmp/r")" = v1.10.0 ] || fail "newest: want v1.10.0"
echo "ok  newest picks v1.10.0 over v1.9.9 and ignores non-vX.Y.Z tags"
printf '%s\n' "$good" | sed 's/^hold = .*/preprod = "agent\/x"/' > "$tmp/c.toml"
run check >/dev/null || fail "preprod key: check exited non-zero"
[ "$(run get wordle preprod)" = agent/x ] || fail "preprod key: get"
echo "ok  preprod key"
