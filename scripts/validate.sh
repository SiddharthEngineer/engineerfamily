#!/usr/bin/env bash
# One validation gate for humans, agents and CI. Run from anywhere; it works on the checkout it lives in.
#
#   scripts/validate.sh   # bash -n on the shell scripts, compose config for each env, nginx -t for each conf
#
# Prints one PASS/FAIL line per step and exits non-zero on the first failure. Uses .env.template, not the
# server-only /srv .env files, so CI and agent worktrees can run it without secrets. Needs Docker (Compose v2).
set -uo pipefail
cd "$(dirname "$0")/.."

case ${1:-} in
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) echo "usage: scripts/validate.sh [-h]" >&2; exit 2 ;;
esac

step() {  # step <name> <command...>
    local name=$1; shift
    local out
    if out=$("$@" 2>&1); then
        echo "PASS  $name"
    else
        echo "FAIL  $name"
        echo "$out" | tail -n 40
        exit 1
    fi
}

shell_files() {  # scripts/*.sh plus the shell scripts in scripts/vps (by shebang)
    ls scripts/*.sh
    for f in scripts/vps/*; do
        head -n 1 "$f" | grep -qE '^#!.*\b(ba)?sh\b' && echo "$f"
    done
}
mapfile -t scripts < <(shell_files)
step "bash -n" bash -c 'for f in "$@"; do bash -n "$f" || exit 1; done' _ "${scripts[@]}"

for env in local preprod prod; do
    step "compose $env" docker compose --env-file .env.template -f docker-compose.base.yml -f "docker-compose.$env.yml" config -q
done

for env in local preprod prod; do
    step "nginx $env" docker run --rm \
        -v "$PWD/services/nginx/nginx.$env.conf:/etc/nginx/conf.d/default.conf:ro" \
        nginx:alpine nginx -t
done
