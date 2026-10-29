# Makefile – common dev and deploy helpers
# Usage: make <target>


.PHONY: help run-app run-streamlit \
	local-up local-down local-build local-logs local-ps \
	up down build restart logs ps site-db-init strelitzia-db-init strelitzia-up strelitzia-deploy strelitzia-logs \
	wordle-deploy wordle-logs \
	preprod-deploy preprod-up preprod-down preprod-build preprod-logs preprod-ps \
	preprod-site-db-init preprod-strelitzia-db-init preprod-strelitzia-up preprod-strelitzia-logs \
	preprod-wordle-deploy preprod-wordle-logs \
	applypilot-db-init applypilot-up applypilot-deploy applypilot-logs \
	preprod-applypilot-db-init preprod-applypilot-up preprod-applypilot-logs \
	shell-app shell-streamlit \
	prod-release deploy-prod check-github-cli \
	prod-changes

# Prod and preprod targets always act on the deploy checkouts in /srv, wherever make runs from (e.g. the dev clone
# in ~/src). Those checkouts hold the untracked .env and htpasswd files and sit next to the pinned Strelitzia
# checkouts. Edits in a dev clone reach them only through a deploy (preprod-deploy, prod-release, strelitzia-deploy, wordle-deploy).
# Compose project names are pinned, not taken from the checkout's directory name: the project name
# prefixes container and volume names, so a renamed checkout would otherwise start with empty volumes.
PROD_DIR ?= /srv/engineerfamily-prod
PREPROD_DIR ?= /srv/engineerfamily-preprod
STRELITZIA_PROD_DIR ?= /srv/Strelitzia-prod
WORDLE_PROD_DIR ?= /srv/Wordle-prod
STRELITZIA_PREPROD_DIR ?= /srv/Strelitzia-preprod
WORDLE_PREPROD_DIR ?= /srv/Wordle-preprod
PROD = docker compose -p engineerfamily --project-directory $(PROD_DIR) \
	-f $(PROD_DIR)/docker-compose.base.yml -f $(PROD_DIR)/docker-compose.prod.yml
PREPROD = docker compose -p engineerfamily-preprod --project-directory $(PREPROD_DIR) \
	-f $(PREPROD_DIR)/docker-compose.base.yml -f $(PREPROD_DIR)/docker-compose.preprod.yml

# components.toml pins each child repo to a tag (scripts/components.py reads it). $(call checkout-pins,<engineerfamily dir>,<env>)
# checks each child out at its pin in /srv/<Child>-<env>, as scripts/vps/engineerfamily-deploy does for prod. A ref
# without components.toml (a rollback to before the pins) leaves the child checkouts as they are.
define checkout-pins
@if [ ! -f $(1)/components.toml ]; then echo "→ no components.toml at this ref; child checkouts left as they are"; else \
		pins=$$(python3 $(1)/scripts/components.py --file $(1)/components.toml list) || exit 1; \
		echo "$$pins" | while IFS="$$(printf '\t')" read -r name repo tag service; do \
			[ -n "$$name" ] || continue; \
			case $$name in \
				strelitzia) cdir=/srv/Strelitzia-$(2) ;; \
				wordle) cdir=/srv/Wordle-$(2) ;; \
				*) echo "unknown component '$$name' in components.toml" >&2; exit 1 ;; \
			esac; \
			git -C $$cdir fetch -q --prune --force --tags origin && git -C $$cdir checkout -q --detach refs/tags/$$tag || exit 1; \
			echo "→ $$name at $$tag"; \
		done; \
	fi
endef
# Preprod floats: $(call checkout-preprod,<engineerfamily dir>) checks each child out at its newest vX.Y.Z tag on origin,
# not at its pin. strelitzia=<tag|branch> / wordle=<tag|branch> override one child; else a component's `preprod` key
# freezes it. Every ref goes through scripts/preprod-ref.sh (a tag or a branch, never a sha). The scripts come from the
# checkout being deployed, or from this Makefile's checkout for a ref that predates them.
define checkout-preprod
@if [ ! -f $(1)/components.toml ]; then echo "→ no components.toml at this ref; child checkouts left as they are"; else \
		s=$(1)/scripts; [ -f $$s/preprod-ref.sh ] || s=$(CURDIR)/scripts; \
		c="python3 $$s/components.py --file $(1)/components.toml"; \
		pins=$$($$c list) || exit 1; \
		echo "$$pins" | while IFS="$$(printf '\t')" read -r name repo tag service; do \
			[ -n "$$name" ] || continue; \
			case $$name in \
				strelitzia) cdir=$(STRELITZIA_PREPROD_DIR); want='$(strelitzia)' ;; \
				wordle) cdir=$(WORDLE_PREPROD_DIR); want='$(wordle)' ;; \
				*) echo "unknown component '$$name' in components.toml" >&2; exit 1 ;; \
			esac; \
			if [ -n "$$want" ]; then why=override; \
			elif want=$$($$c get $$name preprod 2>/dev/null); then why="preprod key"; \
			else why=newest; want=$$($$c newest $$name --remote "$$(git -C $$cdir remote get-url origin)") || exit 1; fi; \
			r=$$(bash $$s/preprod-ref.sh $$cdir "$$want") || exit 2; \
			git -C $$cdir checkout -q --detach $$r || exit 1; \
			echo "→ $$name at $$want ($$why)"; \
		done; \
	fi
endef
# A component's tag as pinned in the prod checkout: the default ref of strelitzia-deploy and wordle-deploy.
pin = $$(python3 $(PROD_DIR)/scripts/components.py get $(1) tag || { echo "no $(1) pin in $(PROD_DIR) (a ref before components.toml?); pass ref=" >&2; exit 1; })

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
	@echo "    site-db-init     Create the engineerfamily role + DB (site permissions) in postgres-db (idempotent)"
	@echo "    strelitzia-db-init Create the strelitzia role + DBs in postgres-db (idempotent)"
	@echo "    strelitzia-up    Rebuild + restart only the Strelitzia dashboard (from /srv/Strelitzia-prod as checked out)"
	@echo "    strelitzia-deploy Check out Strelitzia at its pin (or ref=<sha|tag|origin/trunk>) in /srv/Strelitzia-prod, then strelitzia-up"
	@echo "    strelitzia-logs  Tail the Strelitzia dashboard logs"
	@echo "    wordle-deploy    Check out Wordle at its pin (or ref=<sha|tag|origin/main>) in $(WORDLE_PROD_DIR), rebuild only wordle"
	@echo "    wordle-logs      Tail the Wordle solver logs"
	@echo "    (applypilot-* names still work as deprecated aliases)"
	@echo ""
	@echo "  Preprod (acts on $(PREPROD_DIR), from any directory):"
	@echo "    preprod-deploy   ref=<tag|branch> (required) in $(PREPROD_DIR), the children at their newest tags (strelitzia=/wordle= override), rebuild, reload nginx"
	@echo "    preprod-up       Start preprod containers"
	@echo "    preprod-down     Stop preprod containers"
	@echo "    preprod-build    Rebuild preprod images"
	@echo "    preprod-logs     Tail logs for preprod containers"
	@echo "    preprod-ps       Show preprod container status"
	@echo "    preprod-site-db-init       Create the engineerfamily role + engineerfamily_preprod DB (idempotent)"
	@echo "    preprod-strelitzia-db-init Create the strelitzia role + strelitzia_preprod DB (idempotent)"
	@echo "    preprod-strelitzia-up      Rebuild + restart only the preprod dashboard (from /srv/Strelitzia-preprod)"
	@echo "    preprod-strelitzia-logs    Tail the preprod dashboard logs"
	@echo "    preprod-wordle-deploy      Check out Wordle's newest tag (or ref=<tag|branch>) in $(WORDLE_PREPROD_DIR), rebuild only wordle"
	@echo "    preprod-wordle-logs        Tail the preprod Wordle solver logs"
	@echo ""
	@echo "  Releases:"
	@echo "    prod-release     Ship the newest tag (or v=X.Y.Z) and its pins to prod, then promote what moved (asks; dry=1 previews)"
	@echo "    deploy-prod      Deploy a tag to prod without promoting, for rollbacks (e.g. make deploy-prod ref=v1.4.2)"
	@echo "    prod-changes     Show what the next prod deploy would ship (engineerfamily since the last full release, each child from prod to its pin; v=X.Y.Z)"
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

# The clone's script against the /srv checkout: it works before the first deploy that ships the script.
site-db-init:
	bash $(CURDIR)/scripts/init-site-db.sh prod $(PROD_DIR)

strelitzia-db-init:
	bash $(PROD_DIR)/scripts/init-strelitzia-db.sh

# --force-recreate: the dashboard reads ~/.strelitzia/.env at startup, and compose sees no change when only that file
# changes (e.g. STRELITZIA_AUTH_MODE), so a plain up would leave the old container running.
strelitzia-up:
	$(PROD) up -d --build --force-recreate --no-deps strelitzia

# Prod Strelitzia builds from a detached commit, by default its components.toml pin; nobody edits /srv/Strelitzia-prod by hand.
strelitzia-deploy:
	git -C $(STRELITZIA_PROD_DIR) fetch -q --prune --force --tags origin
	r=$(or $(ref),$(call pin,strelitzia)) && git -C $(STRELITZIA_PROD_DIR) checkout -q --detach $$r
	@echo "→ Strelitzia-prod at $$(git -C $(STRELITZIA_PROD_DIR) log --oneline -1)"
	$(PROD) up -d --build --force-recreate --no-deps strelitzia

strelitzia-logs:
	$(PROD) logs -f --tail=100 strelitzia

# Wordle solver, same shape as strelitzia-deploy: a detached commit of SiddharthEngineer/Wordle in /srv/Wordle-prod.
wordle-deploy:
	git -C $(WORDLE_PROD_DIR) fetch -q --prune --force --tags origin
	r=$(or $(ref),$(call pin,wordle)) && git -C $(WORDLE_PROD_DIR) checkout -q --detach $$r
	@echo "→ Wordle-prod at $$(git -C $(WORDLE_PROD_DIR) log --oneline -1)"
	$(PROD) up -d --build --force-recreate --no-deps wordle

wordle-logs:
	$(PROD) logs -f --tail=100 wordle

# ─── Preprod ─────────────────────────────────────────────
# The everyday way to put an engineerfamily change on preprod: no GitHub workflow, run from the VPS.
#   make preprod-deploy ref=<tag|branch> [strelitzia=<tag|branch>] [wordle=<tag|branch>]
# ref= is required: a vX.Y.Z tag or a branch (main, agent/x, origin/agent/x), never a sha. The children float on their
# newest tags (checkout-preprod above). The local `preprod` branch is just a name here.
# site-version.sh writes services/shared/version.json for the header's version text.
preprod-deploy:
	@test -n '$(ref)' || { echo "preprod-deploy needs ref=<tag|branch> (e.g. ref=main)" >&2; exit 2; }
	@for w in '$(strelitzia)' '$(wordle)'; do [ -z "$$w" ] || bash $(CURDIR)/scripts/preprod-ref.sh --check "$$w" || exit 2; done
	r=$$(bash $(CURDIR)/scripts/preprod-ref.sh $(PREPROD_DIR) '$(ref)') && git -C $(PREPROD_DIR) checkout -q -B preprod $$r
	@echo "→ engineerfamily-preprod at $$(git -C $(PREPROD_DIR) log --oneline -1)"
	$(call checkout-preprod,$(PREPROD_DIR))
	@bash $(PREPROD_DIR)/scripts/site-version.sh preprod $(PREPROD_DIR) 2>/dev/null \
		|| { rm -f $(PREPROD_DIR)/services/shared/version.json; echo "→ no version.json (no site-version.sh at this ref)"; }
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

preprod-site-db-init:
	bash $(CURDIR)/scripts/init-site-db.sh preprod $(PREPROD_DIR)

preprod-strelitzia-db-init:
	bash $(PREPROD_DIR)/scripts/init-strelitzia-db.sh preprod

preprod-strelitzia-up:
	$(PREPROD) up -d --build --force-recreate --no-deps strelitzia

preprod-strelitzia-logs:
	$(PREPROD) logs -f --tail=100 strelitzia

# Wordle alone on preprod: ref=<tag|branch>, default its newest vX.Y.Z tag.
preprod-wordle-deploy:
	w='$(ref)'; [ -n "$$w" ] || w=$$(python3 $(CURDIR)/scripts/components.py newest wordle \
		--remote "$$(git -C $(WORDLE_PREPROD_DIR) remote get-url origin)") || exit 1; \
		r=$$(bash $(CURDIR)/scripts/preprod-ref.sh $(WORDLE_PREPROD_DIR) "$$w") && git -C $(WORDLE_PREPROD_DIR) checkout -q --detach $$r
	@echo "→ Wordle-preprod at $$(git -C $(WORDLE_PREPROD_DIR) log --oneline -1)"
	$(PREPROD) up -d --build --force-recreate --no-deps wordle

preprod-wordle-logs:
	$(PREPROD) logs -f --tail=100 wordle

# Deprecated ApplyPilot names (the Strelitzia runner's config and old habits); remove once nothing uses them.
applypilot-db-init: strelitzia-db-init
applypilot-up: strelitzia-up
applypilot-deploy: strelitzia-deploy
applypilot-logs: strelitzia-logs
preprod-applypilot-db-init: preprod-strelitzia-db-init
preprod-applypilot-up: preprod-strelitzia-up
preprod-applypilot-logs: preprod-strelitzia-logs

# ─── Releases ────────────────────────────────────────────
# The runner tags every PR merge (vX.Y.Z) and keeps a vX.Y pre-release on GitHub (agent-runner `versions`).
#   make prod-release [v=X.Y.Z] [dry=1] → move components.toml to the children's newest tags (one release-pins PR, which
#                                         gets the next tag), or the newest tag (or vX.Y.Z) as tagged; deploy it to prod,
#                                         then promote its release and each moved child's to full
#   make deploy-prod ref=vX.Y.Z    → deploy a tag (children at its pins) without promoting anything: rollbacks
# Both are the user's; agents never run them.

# Read-only: what prod-release would ship next (main with the children at their newest tags, or the newest tag, or
# v=X.Y.Z), with PR links: engineerfamily since prod's release, and each child from what prod runs to its new pin.
prod-changes:
	@STRELITZIA_PROD_DIR=$(STRELITZIA_PROD_DIR) WORDLE_PROD_DIR=$(WORDLE_PROD_DIR) GH='$(GH)' \
		bash $(CURDIR)/scripts/prod-changes.sh $(if $(v),v$(patsubst v%,%,$(v)))

# scripts/prod-release.sh: sync tags, preview, one y/N, the release-pins PR if a child has a newer tag (merged and tagged),
# deploy.yml for the tag (its pins come along), health checks, then promote engineerfamily and each child whose pin
# moved. dry=1 previews and lists the commands; nothing is created or deployed.
prod-release:
	@$(MAKE) check-github-cli
	@PROD='$(PROD)' GH='$(GH)' STRELITZIA_PROD_DIR=$(STRELITZIA_PROD_DIR) WORDLE_PROD_DIR=$(WORDLE_PROD_DIR) \
		bash $(CURDIR)/scripts/prod-release.sh $(if $(filter 1 yes true,$(dry)),--dry-run) $(if $(v),v$(patsubst v%,%,$(v)))

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

# ─── Shells ──────────────────────────────────────────────
shell-app:
	$(PROD) exec app /bin/bash

shell-streamlit:
	$(PROD) exec streamlit /bin/bash