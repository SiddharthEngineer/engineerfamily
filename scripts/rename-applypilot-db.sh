#!/usr/bin/env bash
# One-shot (2026-10): rename an env's Strelitzia DBs and role from applypilot to strelitzia, inside the old
# analytics-db container, then remove that container so the next deploy starts postgres-db on the same volume.
#   rename-applypilot-db.sh [prod]   applypilot, applypilot_test -> strelitzia, strelitzia_test
#   rename-applypilot-db.sh preprod  applypilot_preprod -> strelitzia_preprod
# Run it from the dev clone, before deploying the commit that renamed the service: the /srv checkout is still on the
# old commit. It acts on containers by name and reads only key names from /srv/engineerfamily-<env>/.env.
# Idempotent. The role keeps its password (SCRAM verifiers don't depend on the role name). Delete after both envs ran it.
set -euo pipefail

env="${1:-prod}"
case "$env" in
	prod)    pwvar=STRELITZIA_DB_PASSWORD;         dbs=(applypilot:strelitzia applypilot_test:strelitzia_test) ;;
	preprod) pwvar=STRELITZIA_DB_PASSWORD_PREPROD; dbs=(applypilot_preprod:strelitzia_preprod) ;;
	*) echo "usage: $0 [prod|preprod]" >&2; exit 2 ;;
esac

project=engineerfamily; [ "$env" = preprod ] && project=engineerfamily-preprod
env_file="${ENV_DIR:-/srv/engineerfamily-${env}}/.env"
old="${project}-analytics-db-1"
new="${project}-postgres-db-1"
app="${project}-strelitzia-1"

if ! grep -q "^${pwvar}=." "$env_file"; then
	echo "${env_file} has no ${pwvar}: rename the APPLYPILOT_ key first (same value)" >&2
	exit 1
fi

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }
if ! running "$old"; then
	if running "$new"; then
		echo "${new} is already up: nothing to do"
		exit 0
	fi
	echo "${old} isn't running, so there's nothing to rename in (start it with the old compose first)" >&2
	exit 1
fi

psql_su() { docker exec -i "$old" psql -v ON_ERROR_STOP=1 -U umami -d umami -tA "$@"; }
exists() { [ "$(psql_su -c "SELECT 1 FROM $1 WHERE $2 = '$3'")" = "1" ]; }

if docker inspect "$app" >/dev/null 2>&1; then
	docker stop "$app" >/dev/null
	echo "stopped ${app}"
fi

for pair in "${dbs[@]}"; do
	from="${pair%%:*}" to="${pair##*:}"
	if exists pg_database datname "$to"; then
		exists pg_database datname "$from" && { echo "both ${from} and ${to} exist; sort that out by hand" >&2; exit 1; }
		echo "database ${to} exists"
		continue
	fi
	exists pg_database datname "$from" || { echo "neither ${from} nor ${to} exists" >&2; exit 1; }
	psql_su -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${from}'" >/dev/null
	psql_su -c "ALTER DATABASE ${from} RENAME TO ${to}" >/dev/null
	echo "renamed database ${from} -> ${to}"
done

if exists pg_roles rolname strelitzia; then
	exists pg_roles rolname applypilot && { echo "both roles applypilot and strelitzia exist; sort that out by hand" >&2; exit 1; }
	echo "role strelitzia exists"
else
	psql_su -c "ALTER ROLE applypilot RENAME TO strelitzia" >/dev/null
	echo "renamed role applypilot -> strelitzia"
fi

# Never let the old and new containers share the volume (or fight over port 5432).
docker stop "$old" >/dev/null
docker rm "$old" >/dev/null
echo "removed ${old}"
echo "next: deploy ${env} at the commit that renamed the service (it starts ${new} and ${app})"
