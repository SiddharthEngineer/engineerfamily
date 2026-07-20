# Makefile – common dev and deploy helpers
# Usage: make <target>


.PHONY: help run-app run-streamlit \
	local-up local-down local-build local-logs local-ps \
	up down build restart logs ps \
	preprod-up preprod-down preprod-build preprod-logs preprod-ps \
	shell-app shell-streamlit \
	tag-preprod tag-prod validate-release-tagging sync-release-branch

help:
	@echo ""
	@echo "  Engineer Family – make targets"
	@echo ""
	@echo "  Local dev (no Docker):"
	@echo "    run-app          Run Flask app locally on :5000"
	@echo "    run-streamlit    Run Streamlit app locally on :8501"
	@echo ""
	@echo "  Local (Docker):"
	@echo "    local-up         Start app + Streamlit in Docker for localhost"
	@echo "    local-down       Stop local Docker stack"
	@echo "    local-build      Rebuild local images"
	@echo "    local-logs       Tail logs for local containers"
	@echo "    local-ps         Show local container status"
	@echo ""
	@echo "  Production:"
	@echo "    up               Start all prod containers"
	@echo "    down             Stop all prod containers"
	@echo "    build            Rebuild all images"
	@echo "    restart          Rebuild + restart changed services"
	@echo "    logs             Tail logs for all containers"
	@echo "    ps               Show container status"
	@echo ""
	@echo "  Preprod:"
	@echo "    preprod-up       Start preprod containers"
	@echo "    preprod-down     Stop preprod containers"
	@echo "    preprod-build    Rebuild preprod images"
	@echo "    preprod-logs     Tail logs for preprod containers"
	@echo "    preprod-ps       Show preprod container status"
	@echo ""
	@echo "  Releases:"
	@echo "    tag-preprod      Tag current commit for preprod  (e.g. make tag-preprod v=1.2.3)"
	@echo "    tag-prod         Tag current commit for prod     (e.g. make tag-prod v=1.2.3)"
	@echo "    validate-release-tagging Validate tag branch policy for v=<major.minor.patch>"
	@echo "    sync-release-branch Ensure release branch points to latest tag for v=<major.minor.patch>"
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

local-logs:
	docker compose -f docker-compose.local.yml logs -f --tail=50

local-ps:
	docker compose -f docker-compose.local.yml ps

# ─── Production ──────────────────────────────────────────
up:
	docker compose -f docker-compose.base.yml -f docker-compose.prod.yml up -d --build --force-recreate --remove-orphans

down:
	docker compose -f docker-compose.base.yml -f docker-compose.prod.yml down

logs:
	docker compose -f docker-compose.base.yml -f docker-compose.prod.yml logs -f --tail=50

ps:
	docker compose -f docker-compose.base.yml -f docker-compose.prod.yml ps

# ─── Preprod ─────────────────────────────────────────────
preprod-up:
	docker compose -f docker-compose.base.yml -f docker-compose.preprod.yml up -d --build --force-recreate --remove-orphans

preprod-down:
	docker compose -f docker-compose.base.yml -f docker-compose.preprod.yml down

preprod-logs:
	docker compose -f docker-compose.base.yml -f docker-compose.preprod.yml logs -f --tail=50

preprod-ps:
	docker compose -f docker-compose.base.yml -f docker-compose.preprod.yml ps

# ─── Releases ────────────────────────────────────────────
# Usage: make tag-preprod v=1.2.3  → creates and pushes tag v1.2.3-preprod
#        make tag-prod v=1.2.3     → creates and pushes tag v1.2.3

tag-preprod:
	@test -n "$(v)" || (echo "Usage: make tag-preprod v=1.2.3" && exit 1)
	@command -v gh >/dev/null 2>&1 || (echo "Error: gh CLI not found. Install from https://cli.github.com/" && exit 1)
	@$(MAKE) validate-release-tagging v=$(v)
	@$(MAKE) sync-release-branch v=$(v)
	git tag -f v$(v)-preprod
	git push origin v$(v)-preprod --force
	@echo "→ Triggering deploy of v$(v)-preprod to preprod..."
	gh workflow run deploy.yml --ref main -f environment=preprod -f ref=v$(v)-preprod

tag-prod:
	@test -n "$(v)" || (echo "Usage: make tag-prod v=1.2.3" && exit 1)
	@command -v gh >/dev/null 2>&1 || (echo "Error: gh CLI not found. Install from https://cli.github.com/" && exit 1)
	@$(MAKE) validate-release-tagging v=$(v)
	@$(MAKE) sync-release-branch v=$(v)
	git tag -f v$(v)
	git push origin v$(v) --force
	@echo "→ Triggering deploy of v$(v) to production..."
	gh workflow run deploy.yml --ref main -f environment=prod -f ref=v$(v)

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
	docker compose -f docker-compose.base.yml -f docker-compose.prod.yml exec app /bin/bash

shell-streamlit:
	docker compose -f docker-compose.base.yml -f docker-compose.prod.yml exec streamlit /bin/bash