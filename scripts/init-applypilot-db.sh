#!/usr/bin/env bash
# Create the ApplyPilot role and databases in an env's analytics-db container.
#   init-applypilot-db.sh [prod]   applypilot + applypilot_test, password APPLYPILOT_DB_PASSWORD
#   init-applypilot-db.sh preprod  applypilot_preprod, password APPLYPILOT_DB_PASSWORD_PREPROD
# Idempotent: anything that already exists is skipped. Reads the password
# from the environment or from .env in the repo root.
set -euo pipefail

env="${1:-prod}"
case "$env" in
	prod)    pwvar=APPLYPILOT_DB_PASSWORD;         dbs=(applypilot applypilot_test) ;;
	preprod) pwvar=APPLYPILOT_DB_PASSWORD_PREPROD; dbs=(applypilot_preprod) ;;
	*) echo "usage: $0 [prod|preprod]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
APPLYPILOT_DB_PASSWORD="${!pwvar:-}"
if [ -z "$APPLYPILOT_DB_PASSWORD" ] && [ -f .env ]; then
	APPLYPILOT_DB_PASSWORD="$(sed -n "s/^${pwvar}=//p" .env | tail -n1)"
fi
if [ -z "${APPLYPILOT_DB_PASSWORD:-}" ]; then
	echo "${pwvar} is not set (env or .env)" >&2
	exit 1
fi
if ! [[ "$APPLYPILOT_DB_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
	echo "${pwvar} must be alphanumeric (generate with: openssl rand -hex 24)" >&2
	exit 1
fi

COMPOSE="docker compose -f docker-compose.base.yml -f docker-compose.${env}.yml"
psql_su() { $COMPOSE exec -T analytics-db psql -v ON_ERROR_STOP=1 -U umami -d umami -tA "$@"; }

if [ "$(psql_su -c "SELECT 1 FROM pg_roles WHERE rolname = 'applypilot'")" = "1" ]; then
	echo "role applypilot exists"
else
	psql_su -c "CREATE ROLE applypilot LOGIN PASSWORD '${APPLYPILOT_DB_PASSWORD}'" >/dev/null
	echo "created role applypilot"
fi

for db in "${dbs[@]}"; do
	if [ "$(psql_su -c "SELECT 1 FROM pg_database WHERE datname = '${db}'")" = "1" ]; then
		echo "database ${db} exists"
	else
		psql_su -c "CREATE DATABASE ${db} OWNER applypilot" >/dev/null
		echo "created database ${db}"
	fi
done
