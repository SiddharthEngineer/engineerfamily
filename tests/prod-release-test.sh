#!/usr/bin/env bash
# scripts/prod-release.sh and scripts/prod-changes.sh against temp repos: three origins (engineerfamily tags pin
# different Strelitzia and Wordle tags), "prod" checkouts at older tags, and logging stubs for gh, agent-runner, curl
# and docker on PATH. Never touches /srv, the real gh or the runner. One `ok` line per case; exits non-zero on the first failure.
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
pins() {  # pins <dir> <strelitzia tag> <wordle tag>
    printf '[strelitzia]\nrepo = "SiddharthEngineer/Strelitzia"\ntag = "%s"\nservice = "strelitzia"\n\n' "$2" >"$1/components.toml"
    printf '[wordle]\nrepo = "SiddharthEngineer/Wordle"\ntag = "%s"\nservice = "wordle"\n' "$3" >>"$1/components.toml"
}
publish() {  # publish <work dir> <bare origin>
    git init -q --bare "$2"
    git -C "$1" remote add origin "$2"
    git -C "$1" push -q --tags origin main
}

# Children: Strelitzia v1.0.0 v1.1.0 v1.2.0 (v1.2.0 not pinned by any tag), Wordle v1.0.0 v1.0.1.
for child in Strelitzia Wordle; do git init -q "$tmp/work-$child"; done
commit "$tmp/work-Strelitzia" "strelitzia one" v1.0.0
commit "$tmp/work-Strelitzia" "strelitzia two (#11)" v1.1.0
commit "$tmp/work-Strelitzia" "strelitzia three (#12)" v1.2.0
commit "$tmp/work-Wordle" "wordle one" v1.0.0
commit "$tmp/work-Wordle" "wordle two (#5)" v1.0.1
# engineerfamily: v1.0.0 (s 1.0.0, w 1.0.0), v1.1.0 (s 1.1.0), v1.2.0 (s 1.1.0, w 1.0.1), then one untagged commit.
ef=$tmp/work-ef
git init -q "$ef"
pins "$ef" v1.0.0 v1.0.0; commit "$ef" "site one" v1.0.0
pins "$ef" v1.1.0 v1.0.0; commit "$ef" "Pin strelitzia v1.1.0 (#20)" v1.1.0
pins "$ef" v1.1.0 v1.0.1; commit "$ef" "Pin wordle v1.0.1 (#21)" v1.2.0
commit "$ef" "site after (#22)"
for r in Strelitzia Wordle ef; do publish "$tmp/work-$r" "$tmp/$r.git"; done

# Dev clones (the engineerfamily one runs the scripts under test) and "prod" checkouts at v1.0.0.
git clone -q "$tmp/ef.git" "$tmp/dev-ef"
mkdir -p "$tmp/dev-ef/scripts"
cp scripts/prod-changes.sh scripts/prod-release.sh scripts/components.py "$tmp/dev-ef/scripts/"
for child in Strelitzia Wordle; do
    git clone -q "$tmp/$child.git" "$tmp/dev-$child"
    git clone -q "$tmp/$child.git" "$tmp/$child-prod"
    git -C "$tmp/$child-prod" checkout -q --detach v1.0.0
done
export STRELITZIA_DEV_DIR=$tmp/dev-Strelitzia WORDLE_DEV_DIR=$tmp/dev-Wordle
export STRELITZIA_PROD_DIR=$tmp/Strelitzia-prod WORDLE_PROD_DIR=$tmp/Wordle-prod

# Stubs: each logs its call to $CALLS. FAKE_RELEASE is prod's full release; FAKE_PIN_PRS the open pin-bump PRs
# ("number<TAB>title" lines); FAKE_SYNC_FAIL a repo whose sync exits 3; FAKE_CURL_FAIL a URL part that never answers.
mkdir "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$CALLS"
case "$1 $2" in
    "auth status") ;;
    "release list") echo "${FAKE_RELEASE:-}" ;;
    "pr list") [ -z "${FAKE_PIN_PRS:-}" ] || printf '%b\n' "$FAKE_PIN_PRS" ;;
    "run list") if [[ " $* " == *" --event "* ]]; then echo 42; else echo 41; fi ;;
    "api "*|"workflow run"|"run watch") ;;
    *) echo "gh stub: unexpected $*" >&2; exit 1 ;;
esac
EOF
cat >"$tmp/bin/agent-runner" <<'EOF'
#!/usr/bin/env bash
echo "agent-runner $*" >>"$CALLS"
[ "$1 $2 $3" != "versions sync ${FAKE_SYNC_FAIL:-none}" ] || exit 3
EOF
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$CALLS"
url=${!#}
if [ -n "${FAKE_CURL_FAIL:-}" ] && [[ $url == *"$FAKE_CURL_FAIL"* ]]; then
    [[ " $* " == *" -w "* ]] && echo 502
    exit 22
fi
if [[ " $* " == *" -w "* ]]; then echo 200; else echo '{"ok": true, "words": 5}'; fi
EOF
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"$CALLS"
EOF
chmod +x "$tmp/bin/"*
export PATH=$tmp/bin:$PATH GH=$tmp/bin/gh HEALTH_WAIT=0 PROD="docker compose -p engineerfamily-test"
export CALLS=$tmp/calls.log

release() {  # release <answer> <args...>: run prod-release.sh with a fresh call log; output in $out, exit code in $rc
    : >"$CALLS"
    rc=0
    out=$(echo "$1" | bash "$tmp/dev-ef/scripts/prod-release.sh" "${@:2}" 2>&1) || rc=$?
}
calls() { grep -c -- "$1" "$CALLS" || true; }
expect() {  # expect <case> <condition text> <test...>
    local name=$1 what=$2; shift 2
    "$@" || fail "$name: $what
--- output (exit $rc) ---
$out
--- calls ---
$(cat "$CALLS")"
}
has() { grep -qF -- "$1" <<<"$out"; }
lacks() { ! grep -qF -- "$1" <<<"$out"; }

export FAKE_RELEASE=v1.0.0

# (a) only Strelitzia's pin moved: one deploy, then promotes for engineerfamily and strelitzia only.
release y v1.1.0
expect a "exit 0" [ "$rc" = 0 ]
expect a "one deploy" [ "$(calls 'gh workflow run deploy.yml --ref main -f environment=prod -f ref=v1.1.0')" = 1 ]
expect a "promote engineerfamily" [ "$(calls 'versions promote engineerfamily v1.1.0')" = 1 ]
expect a "promote strelitzia" [ "$(calls 'versions promote strelitzia v1.1.0')" = 1 ]
expect a "no wordle promote" [ "$(calls 'versions promote wordle')" = 0 ]
expect a "health checks ran" [ "$(calls 'docker compose -p engineerfamily-test exec -T strelitzia curl')" = 1 ]
expect a "summary" has "✓ v1.1.0 on prod: strelitzia v1.1.0, wordle v1.0.0"
expect a "preview" has "strelitzia: v1.0.0 → v1.1.0"
echo "ok  (a) only strelitzia moved: deploy, promote engineerfamily + strelitzia"

# (b) both pins moved (the default target, the newest tag v1.2.0).
release y
expect b "exit 0" [ "$rc" = 0 ]
expect b "deploy v1.2.0" [ "$(calls 'gh workflow run deploy.yml --ref main -f environment=prod -f ref=v1.2.0')" = 1 ]
expect b "promotes" [ "$(calls 'versions promote engineerfamily v1.2.0')$(calls 'versions promote strelitzia v1.1.0')$(calls 'versions promote wordle v1.0.1')" = 111 ]
expect b "not in it" has "site after (#22)"
expect b "wordle log" has "wordle two (#5)"
echo "ok  (b) both pins moved: both children promoted"

# (c) answer n: no deploy, no promote.
release n v1.2.0
expect c "exit non-zero" [ "$rc" != 0 ]
expect c "prompt" has "Ship v1.2.0 to prod? [y/N]"
expect c "no deploy" [ "$(calls 'workflow run')" = 0 ]
expect c "no promote" [ "$(calls 'versions promote')" = 0 ]
echo "ok  (c) answer n: nothing deployed or promoted"

# (d) a health check fails: no promote, and the rollback hint names prod's old tag.
FAKE_CURL_FAIL=wordle/api/health release y v1.2.0
expect d "exit non-zero" [ "$rc" != 0 ]
expect d "deployed" [ "$(calls 'workflow run')" = 1 ]
expect d "6 tries" [ "$(calls 'wordle/api/health')" = 6 ]
expect d "no promote" [ "$(calls 'versions promote')" = 0 ]
expect d "rollback hint" has "make deploy-prod ref=v1.0.0"
echo "ok  (d) health check fails: nothing promoted, rollback hint names v1.0.0"

# (e) a target older than prod's tag is refused before the prompt.
FAKE_RELEASE=v1.1.0 release y v1.0.0
expect e "exit non-zero" [ "$rc" != 0 ]
expect e "refused" has "v1.0.0 is older than prod's v1.1.0"
expect e "no prompt" lacks "Ship v1.0.0"
expect e "no deploy" [ "$(calls 'workflow run')$(calls 'versions promote')" = 00 ]
echo "ok  (e) older target refused before the prompt"

# (f) sync exits 3 for wordle: stops with the M4 hint.
FAKE_SYNC_FAIL=wordle release y
expect f "exit non-zero" [ "$rc" != 0 ]
expect f "M4 hint" has "wordle is waiting for a promote"
expect f "M4" has "ROADMAP M4"
expect f "no prompt" lacks "Ship "
expect f "no deploy" [ "$(calls 'workflow run')" = 0 ]
echo "ok  (f) sync exit 3 for wordle: stops with the M4 hint"

# (g) --dry-run (make prod-release dry=1): sync --dry-run, the preview and the commands; no deploy or promote.
release y --dry-run
expect g "exit 0" [ "$rc" = 0 ]
expect g "sync dry" [ "$(calls 'versions sync .* --dry-run')" = 3 ]
expect g "no prompt" lacks "Ship "
expect g "lists the promote" has "agent-runner versions promote wordle v1.0.1"
expect g "no deploy" [ "$(calls 'workflow run')$(calls 'versions promote')$(calls 'run watch')" = 000 ]
echo "ok  (g) dry run: preview and commands, nothing deployed or promoted"

# (h) a child tag newer than the pin, with an open pin-bump PR: `not pinned yet` names it.
: >"$CALLS"
rc=0
out=$(FAKE_PIN_PRS='83\tPin strelitzia v1.2.0' bash "$tmp/dev-ef/scripts/prod-changes.sh" v1.2.0 2>&1) || rc=$?
expect h "exit 0" [ "$rc" = 0 ]
expect h "names the PR" has "not pinned yet: v1.2.0 (pin-bump PR #83"
expect h "wordle has none" lacks "not pinned yet: v1.0"
out=$(bash "$tmp/dev-ef/scripts/prod-changes.sh" --plan v1.2.0 2>&1)
expect h "plan lines" [ "$out" = "$(printf 'engineerfamily\tv1.0.0\tv1.2.0\tnew\nstrelitzia\tv1.0.0\tv1.1.0\tnew\nwordle\tv1.0.0\tv1.0.1\tnew')" ]
echo "ok  (h) a newer child tag: not pinned yet names the open pin-bump PR"
