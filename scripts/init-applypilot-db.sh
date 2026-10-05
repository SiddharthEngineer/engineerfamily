#!/usr/bin/env bash
# Create the ApplyPilot role and databases in the prod analytics-db container.
# Idempotent: anything that already exists is skipped. Reads APPLYPILOT_DB_PASSWORD
# from the environment or from .env in the repo root.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ -z "${APPLYPILOT_DB_PASSWORD:-}" ] && [ -f .env ]; then
	APPLYPILOT_DB_PASSWORD="$(sed -n 's/^APPLYPILOT_DB_PASSWORD=//p' .env | tail -n1)"
fi
if [ -z "${APPLYPILOT_DB_PASSWORD:-}" ]; then
	echo "APPLYPILOT_DB_PASSWORD is not set (env or .env)" >&2
	exit 1
fi
if ! [[ "$APPLYPILOT_DB_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
	echo "APPLYPILOT_DB_PASSWORD must be alphanumeric (generate with: openssl rand -hex 24)" >&2
	exit 1
fi

COMPOSE="docker compose -f docker-compose.base.yml -f docker-compose.prod.yml"
psql_su() { $COMPOSE exec -T analytics-db psql -v ON_ERROR_STOP=1 -U umami -d umami -tA "$@"; }

if [ "$(psql_su -c "SELECT 1 FROM pg_roles WHERE rolname = 'applypilot'")" = "1" ]; then
	echo "role applypilot exists"
else
	psql_su -c "CREATE ROLE applypilot LOGIN PASSWORD '${APPLYPILOT_DB_PASSWORD}'" >/dev/null
	echo "created role applypilot"
fi

for db in applypilot applypilot_test; do
	if [ "$(psql_su -c "SELECT 1 FROM pg_database WHERE datname = '${db}'")" = "1" ]; then
		echo "database ${db} exists"
	else
		psql_su -c "CREATE DATABASE ${db} OWNER applypilot" >/dev/null
		echo "created database ${db}"
	fi
done
