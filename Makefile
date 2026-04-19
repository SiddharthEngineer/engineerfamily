# Makefile – common dev and deploy helpers
# Usage: make <target>


.PHONY: help run-app run-streamlit local-up local-down up down logs ps build restart \
	preprod-up preprod-down shell-app shell-streamlit \
	tag-preprod tag-prod validate-release-tagging sync-release-branch

help:
	@echo ""
	@echo "  Engineer Family – make targets"
	@echo ""
	@echo "  Local dev (no Docker):"
	@echo "    run-app          Run Flask app locally on :5000"
	@echo "    run-streamlit    Run Streamlit app locally on :8501"
	@echo "    local-up         Start app + Streamlit in Docker for localhost"
	@echo "    local-down       Stop local Docker stack"
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
	docker compose --profile local up -d --build app streamlit

local-down:
	docker compose down

# ─── Production ──────────────────────────────────────────
up:
	docker compose --profile prod up -d

down:
	docker compose --profile prod down

build:
	docker compose --profile prod build

restart:
	docker compose --profile prod up -d --build --remove-orphans

logs:
	docker compose --profile prod logs -f --tail=50

ps:
	docker compose ps

# ─── Preprod ─────────────────────────────────────────────
preprod-up:
	docker compose -f docker-compose.yml -f docker-compose.preprod.yml --profile preprod up -d --build

preprod-down:
	docker compose -f docker-compose.yml -f docker-compose.preprod.yml --profile preprod down

# ─── Releases ────────────────────────────────────────────
# Usage: make tag-preprod v=1.2.3  → creates and pushes tag v1.2.3-preprod
#        make tag-prod v=1.2.3     → creates and pushes tag v1.2.3

tag-preprod:
	@test -n "$(v)" || (echo "Usage: make tag-preprod v=1.2.3" && exit 1)
	@$(MAKE) validate-release-tagging v=$(v)
	git tag v$(v)-preprod
	git push origin v$(v)-preprod
	@$(MAKE) sync-release-branch v=$(v)
	@echo "→ Deploying v$(v)-preprod to preprod..."

tag-prod:
	@test -n "$(v)" || (echo "Usage: make tag-prod v=1.2.3" && exit 1)
	@$(MAKE) validate-release-tagging v=$(v)
	git tag v$(v)
	git push origin v$(v)
	@$(MAKE) sync-release-branch v=$(v)
	@echo "→ Deploying v$(v) to production..."

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
	docker compose exec app /bin/bash

shell-streamlit:
	docker compose exec streamlit /bin/bash