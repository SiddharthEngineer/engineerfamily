#!/usr/bin/env bash
# Create the site permissions role and database (services/app/perms.py) in an env's postgres-db container.
#   init-site-db.sh [prod] [<checkout>]   engineerfamily, password SITE_DB_PASSWORD
#   init-site-db.sh preprod [<checkout>]  engineerfamily_preprod, password SITE_DB_PASSWORD_PREPROD
# <checkout> (default: the repo this script is in) gives the .env and compose files, so the dev clone's copy can set up
# /srv/engineerfamily-prod before the first deploy that ships this script (`make site-db-init` does that).
# Idempotent: anything that already exists is skipped. Reads the password
# from the environment or from <checkout>/.env. The app creates its tables on startup.
set -euo pipefail

env="${1:-prod}"
dir="$(cd "${2:-$(dirname "$0")/..}" && pwd)"
case "$env" in
	prod)    pwvar=SITE_DB_PASSWORD;         db=engineerfamily ;;
	preprod) pwvar=SITE_DB_PASSWORD_PREPROD; db=engineerfamily_preprod ;;
	*) echo "usage: $0 [prod|preprod] [<checkout>]" >&2; exit 2 ;;
esac

cd "$dir"
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
COMPOSE="docker compose -p ${project} --project-directory ${dir} -f ${dir}/docker-compose.base.yml -f ${dir}/docker-compose.${env}.yml"
psql_su() { $COMPOSE exec -T postgres-db psql -v ON_ERROR_STOP=1 -U umami -d umami -tA "$@"; }

if [ "$(psql_su -c "SELECT 1 FROM pg_roles WHERE rolname = 'engineerfamily'")" = "1" ]; then
	echo "role engineerfamily exists"
else
	psql_su -c "CREATE ROLE engineerfamily LOGIN PASSWORD '${DB_PASSWORD}'" >/dev/null
	echo "created role engineerfamily"
fi

if [ "$(psql_su -c "SELECT 1 FROM pg_database WHERE datname = '${db}'")" = "1" ]; then
	echo "database ${db} exists"
else
	psql_su -c "CREATE DATABASE ${db} OWNER engineerfamily" >/dev/null
	echo "created database ${db}"
fi
