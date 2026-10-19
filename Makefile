# Makefile – common dev and deploy helpers
# Usage: make <target>


.PHONY: help run-app run-streamlit \
	local-up local-down local-build local-logs local-ps \
	up down build restart logs ps strelitzia-db-init strelitzia-db-rename strelitzia-up strelitzia-deploy strelitzia-logs \
	preprod-deploy preprod-up preprod-down preprod-build preprod-logs preprod-ps \
	preprod-strelitzia-db-init preprod-strelitzia-db-rename preprod-strelitzia-up preprod-strelitzia-logs \
	applypilot-db-init applypilot-up applypilot-deploy applypilot-logs \
	preprod-applypilot-db-init preprod-applypilot-up preprod-applypilot-logs \
	shell-app shell-streamlit \
	tag-preprod tag-prod deploy-preprod deploy-prod validate-release-tagging sync-release-branch check-github-cli \
	prod-changes

# Prod and preprod targets always act on the deploy checkouts in /srv, wherever make runs from (e.g. the dev clone
# in ~/src). Those checkouts hold the untracked .env and htpasswd files and sit next to the pinned Strelitzia
# checkouts. Edits in a dev clone reach them only through a deploy (tag-preprod/tag-prod, strelitzia-deploy).
# Compose project names are pinned, not taken from the checkout's directory name: the project name
# prefixes container and volume names, so a renamed checkout would otherwise start with empty volumes.
PROD_DIR ?= /srv/engineerfamily-prod
PREPROD_DIR ?= /srv/engineerfamily-preprod
STRELITZIA_PROD_DIR ?= /srv/Strelitzia-prod
PROD = docker compose -p engineerfamily --project-directory $(PROD_DIR) \
	-f $(PROD_DIR)/docker-compose.base.yml -f $(PROD_DIR)/docker-compose.prod.yml
PREPROD = docker compose -p engineerfamily-preprod --project-directory $(PREPROD_DIR) \
	-f $(PREPROD_DIR)/docker-compose.base.yml -f $(PREPROD_DIR)/docker-compose.preprod.yml

# Make does not load interactive shell configuration, so also check the
# standard Homebrew locations used on macOS.
GH ?= $(shell command -v gh 2>/dev/null || { \
	for path in /opt/homebrew/bin/gh /usr/local/bin/gh; do \
		if [ -x "$$path" ]; then echo "$$path"; break; fi; \
	done; \
})

help:
	@echo ""
	@echo "  Engineer Family – make targets"
	@echo ""
	@echo "  Local dev (no Docker):"
	@echo "    run-app          Run Flask app locally on :5000"
	@echo "    run-streamlit    Run Streamlit app locally on :8501"
	@echo ""
	@echo "  Local (Docker):"
	@echo "    local-up         Start app in Docker for localhost (COMPOSE_PROFILES=streamlit adds Streamlit)"
	@echo "    local-down       Stop local Docker stack"
	@echo "    local-build      Rebuild local images"
	@echo "    local-logs       Tail logs for local containers"
	@echo "    local-ps         Show local container status"
	@echo ""
	@echo "  Production (acts on $(PROD_DIR), from any directory):"
	@echo "    up               Start all prod containers"
	@echo "    down             Stop all prod containers"
	@echo "    build            Rebuild all images"
	@echo "    restart          Rebuild + restart changed services"
	@echo "    logs             Tail logs for all containers"
	@echo "    ps               Show container status"
	@echo "    strelitzia-db-init Create the strelitzia role + DBs in postgres-db (idempotent)"
	@echo "    strelitzia-db-rename One-shot: rename the applypilot DBs + role to strelitzia, remove analytics-db (then deploy)"
	@echo "    strelitzia-up    Rebuild + restart only the Strelitzia dashboard (from /srv/Strelitzia-prod as checked out)"
	@echo "    strelitzia-deploy Check out Strelitzia origin/trunk (or ref=<sha|tag>) in /srv/Strelitzia-prod, then strelitzia-up"
	@echo "    strelitzia-logs  Tail the Strelitzia dashboard logs"
	@echo "    (applypilot-* names still work as deprecated aliases)"
	@echo ""
	@echo "  Preprod (acts on $(PREPROD_DIR), from any directory):"
	@echo "    preprod-deploy   Check out origin/main (or ref=<sha|tag|origin/branch>) in $(PREPROD_DIR), rebuild, reload nginx"
	@echo "    preprod-up       Start preprod containers"
	@echo "    preprod-down     Stop preprod containers"
	@echo "    preprod-build    Rebuild preprod images"
	@echo "    preprod-logs     Tail logs for preprod containers"
	@echo "    preprod-ps       Show preprod container status"
	@echo "    preprod-strelitzia-db-init Create the strelitzia role + strelitzia_preprod DB (idempotent)"
	@echo "    preprod-strelitzia-db-rename One-shot: rename applypilot_preprod + role to strelitzia, remove analytics-db"
	@echo "    preprod-strelitzia-up      Rebuild + restart only the preprod dashboard (from /srv/Strelitzia-preprod)"
	@echo "    preprod-strelitzia-logs    Tail the preprod dashboard logs"
	@echo ""
	@echo "  Releases:"
	@echo "    tag-preprod      Tag current commit for preprod         (e.g. make tag-preprod v=1.2.3)"
	@echo "    deploy-preprod   Trigger deploy of tagged version       (e.g. make deploy-preprod ref=v1.2.3-preprod)"
	@echo "    tag-prod         Tag current commit for prod            (e.g. make tag-prod v=1.2.3)"
	@echo "    deploy-prod      Trigger deploy of tagged version       (e.g. make deploy-prod ref=v1.2.3)"
	@echo "    validate-release-tagging Validate tag branch policy for v=<major.minor.patch>"
	@echo "    sync-release-branch Ensure release branch points to latest tag for v=<major.minor.patch>"
	@echo "    prod-changes     Show what the next prod deploy would ship (engineerfamily since the last prod tag, Strelitzia since prod)"
	@echo ""
	@echo "  Utilities:"
	@echo "    shell-app        Open shell in app container"
	@echo "    shell-streamlit  Open shell in Streamlit container"
	@echo ""

# ─── Local dev ───────────────────────────────────────────
# Each service has its own venv at services/<name>/.venv
# First time: cd services/app && python -m venv .venv && pip install -r requirements.txt

run-app:
	cd services/app && \
	  . .venv/bin/activate && \
	  FLASK_ENV=development FLASK_DEBUG=1 flask --app app run --port 5000

run-streamlit:
	cd services/streamlit && \
	  . .venv/bin/activate && \
	  streamlit run app.py --server.port 8501

local-up:
	docker compose -f docker-compose.local.yml up -d --build --force-recreate --remove-orphans

local-down:
	docker compose -f docker-compose.local.yml down

local-build:
	docker compose -f docker-compose.local.yml build

local-logs:
	docker compose -f docker-compose.local.yml logs -f --tail=50

local-ps:
	docker compose -f docker-compose.local.yml ps

# ─── Production ──────────────────────────────────────────
up:
	$(PROD) up -d --build --force-recreate --remove-orphans

down:
	$(PROD) down

build:
	$(PROD) build

# Recreates only services whose image or config changed (`up` force-recreates everything).
restart:
	$(PROD) up -d --build --remove-orphans

logs:
	$(PROD) logs -f --tail=50

ps:
	$(PROD) ps

strelitzia-db-init:
	bash $(PROD_DIR)/scripts/init-strelitzia-db.sh

# One-shot (2026-10), run from this clone before deploying the service rename: the /srv checkout doesn't have the script yet.
strelitzia-db-rename:
	bash $(CURDIR)/scripts/rename-applypilot-db.sh prod

# --force-recreate: the dashboard reads ~/.strelitzia/.env at startup, and compose sees no change when only that file
# changes (e.g. STRELITZIA_AUTH_MODE), so a plain up would leave the old container running.
strelitzia-up:
	$(PROD) up -d --build --force-recreate --no-deps strelitzia

# Prod Strelitzia builds from a detached, pinned commit; nobody edits /srv/Strelitzia-prod by hand.
strelitzia-deploy:
	git -C $(STRELITZIA_PROD_DIR) fetch -q --prune origin
	git -C $(STRELITZIA_PROD_DIR) checkout -q --detach $(or $(ref),origin/trunk)
	@echo "→ Strelitzia-prod at $$(git -C $(STRELITZIA_PROD_DIR) log --oneline -1)"
	$(PROD) up -d --build --force-recreate --no-deps strelitzia

strelitzia-logs:
	$(PROD) logs -f --tail=100 strelitzia

# ─── Preprod ─────────────────────────────────────────────
# The everyday way to put an engineerfamily change on preprod: no tag and no GitHub workflow, run from the VPS.
# Same steps as scripts/vps/engineerfamily-deploy, but at any commit. The `preprod` branch on GitHub moves only with
# tag deploys (deploy-preprod), so it can lag behind what this put on preprod.
preprod-deploy:
	git -C $(PREPROD_DIR) fetch -q --prune --tags origin
	git -C $(PREPROD_DIR) checkout -q -B preprod $(or $(ref),origin/main)
	@echo "→ engineerfamily-preprod at $$(git -C $(PREPROD_DIR) log --oneline -1)"
	$(PREPROD) up -d --build --remove-orphans
# nginx.conf is a single-file bind mount: git checkout swaps its inode, so a reload would
# keep the old config. Recreate the container instead.
	$(PREPROD) up -d --force-recreate --no-deps nginx

preprod-up:
	$(PREPROD) up -d --build --force-recreate --remove-orphans

preprod-down:
	$(PREPROD) down

preprod-build:
	$(PREPROD) build

preprod-logs:
	$(PREPROD) logs -f --tail=50

preprod-ps:
	$(PREPROD) ps

preprod-strelitzia-db-init:
	bash $(PREPROD_DIR)/scripts/init-strelitzia-db.sh preprod

preprod-strelitzia-db-rename:
	bash $(CURDIR)/scripts/rename-applypilot-db.sh preprod

preprod-strelitzia-up:
	$(PREPROD) up -d --build --force-recreate --no-deps strelitzia

preprod-strelitzia-logs:
	$(PREPROD) logs -f --tail=100 strelitzia

# Deprecated ApplyPilot names (the Strelitzia runner's config and old habits); remove once nothing uses them.
applypilot-db-init: strelitzia-db-init
applypilot-up: strelitzia-up
applypilot-deploy: strelitzia-deploy
applypilot-logs: strelitzia-logs
preprod-applypilot-db-init: preprod-strelitzia-db-init
preprod-applypilot-up: preprod-strelitzia-up
preprod-applypilot-logs: preprod-strelitzia-logs

# ─── Releases ────────────────────────────────────────────
# Usage: make tag-preprod v=1.2.3     → creates and pushes tag v1.2.3-preprod
#        make deploy-preprod ref=v1.2.3-preprod → triggers deploy to preprod
#        make tag-prod v=1.2.3        → creates and pushes tag v1.2.3
#        make deploy-prod ref=v1.2.3  → triggers deploy to prod

# Read-only: what deploy-prod / strelitzia-deploy would ship next, with PR links. Run it before a prod deploy.
prod-changes:
	@bash $(CURDIR)/scripts/prod-changes.sh $(STRELITZIA_PROD_DIR)

tag-preprod:
	@test -n "$(v)" || (echo "Usage: make tag-preprod v=1.2.3" && exit 1)
	@$(MAKE) check-github-cli
	@$(MAKE) validate-release-tagging v=$(v)
	@$(MAKE) sync-release-branch v=$(v)
	git tag -f v$(v)-preprod
	git push origin v$(v)-preprod --force
	@echo "✓ Tagged v$(v)-preprod"

tag-prod:
	@test -n "$(v)" || (echo "Usage: make tag-prod v=1.2.3" && exit 1)
	@$(MAKE) check-github-cli
	@$(MAKE) validate-release-tagging v=$(v)
	@$(MAKE) sync-release-branch v=$(v)
	git tag -f v$(v)
	git push origin v$(v) --force
	@echo "✓ Tagged v$(v)"

deploy-preprod:
	@test -n "$(ref)" || (echo "Usage: make deploy-preprod ref=v1.2.3-preprod" && exit 1)
	@$(MAKE) check-github-cli
	@echo "→ Triggering deploy of $(ref) to preprod..."
	"$(GH)" workflow run deploy.yml --ref main -f environment=preprod -f ref=$(ref)

deploy-prod:
	@test -n "$(ref)" || (echo "Usage: make deploy-prod ref=v1.2.3" && exit 1)
	@$(MAKE) check-github-cli
	@echo "→ Triggering deploy of $(ref) to production..."
	"$(GH)" workflow run deploy.yml --ref main -f environment=prod -f ref=$(ref)

check-github-cli:
	@if [ -z "$(GH)" ] || [ ! -x "$(GH)" ]; then \
		echo "Error: GitHub CLI (gh) not found. Git and GitHub CLI are separate programs."; \
		echo "Install gh from https://cli.github.com/ or run make with GH=/path/to/gh."; \
		exit 1; \
	fi
	@if ! "$(GH)" auth status --hostname github.com >/dev/null 2>&1; then \
		echo "Error: GitHub CLI is not authenticated."; \
		echo "Run '$(GH) auth login' or set GH_TOKEN to a GitHub token."; \
		exit 1; \
	fi

delete-tag:
	git tag -d $(v)
	git push origin --delete $(v)

# Policy gate that must pass before creating any tag.
validate-release-tagging:
	@test -n "$(v)" || (echo "Usage: make validate-release-tagging v=1.2.3" && exit 1)
	@./scripts/release_branch_sync.sh validate "$(v)"

# Ensures a branch named release-v<major>.<minor> exists and enforces tagging
# policy: tags must be set from main or the matching release branch.
sync-release-branch:
	@test -n "$(v)" || (echo "Usage: make sync-release-branch v=1.2.3" && exit 1)
	@./scripts/release_branch_sync.sh sync "$(v)"

# ─── Shells ──────────────────────────────────────────────
shell-app:
	$(PROD) exec app /bin/bash

shell-streamlit:
	$(PROD) exec streamlit /bin/bash