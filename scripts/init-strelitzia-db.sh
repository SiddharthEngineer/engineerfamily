#!/usr/bin/env bash
# Create the Strelitzia role and databases in an env's postgres-db container.
#   init-strelitzia-db.sh [prod]   strelitzia + strelitzia_test, password STRELITZIA_DB_PASSWORD
#   init-strelitzia-db.sh preprod  strelitzia_preprod, password STRELITZIA_DB_PASSWORD_PREPROD
# Idempotent: anything that already exists is skipped. Reads the password
# from the environment or from .env in the repo root.
set -euo pipefail

env="${1:-prod}"
case "$env" in
	prod)    pwvar=STRELITZIA_DB_PASSWORD;         dbs=(strelitzia strelitzia_test) ;;
	preprod) pwvar=STRELITZIA_DB_PASSWORD_PREPROD; dbs=(strelitzia_preprod) ;;
	*) echo "usage: $0 [prod|preprod]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
DB_PASSWORD="${!pwvar:-}"
if [ -z "$DB_PASSWORD" ] && [ -f .env ]; then
	DB_PASSWORD="$(sed -n "s/^${pwvar}=//p" .env | tail -n1)"
fi
if [ -z "${DB_PASSWORD:-}" ]; then
	echo "${pwvar} is not set (env or .env)" >&2
	exit 1
fi
if ! [[ "$DB_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
	echo "${pwvar} must be alphanumeric (generate with: openssl rand -hex 24)" >&2
	exit 1
fi

project=engineerfamily; [ "$env" = preprod ] && project=engineerfamily-preprod
COMPOSE="docker compose -p ${project} -f docker-compose.base.yml -f docker-compose.${env}.yml"
psql_su() { $COMPOSE exec -T postgres-db psql -v ON_ERROR_STOP=1 -U umami -d umami -tA "$@"; }

if [ "$(psql_su -c "SELECT 1 FROM pg_roles WHERE rolname = 'strelitzia'")" = "1" ]; then
	echo "role strelitzia exists"
else
	psql_su -c "CREATE ROLE strelitzia LOGIN PASSWORD '${DB_PASSWORD}'" >/dev/null
	echo "created role strelitzia"
fi

for db in "${dbs[@]}"; do
	if [ "$(psql_su -c "SELECT 1 FROM pg_database WHERE datname = '${db}'")" = "1" ]; then
		echo "database ${db} exists"
	else
		psql_su -c "CREATE DATABASE ${db} OWNER strelitzia" >/dev/null
		echo "created database ${db}"
	fi
done
