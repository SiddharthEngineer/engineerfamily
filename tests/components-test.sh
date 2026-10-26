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
