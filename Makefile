# Makefile – common dev and deploy helpers
# Usage: make <target>

.PHONY: help run-siddharth run-suryan up down logs ps build restart \
        preprod-up preprod-down shell-siddharth shell-suryan \
        tag-preprod tag-prod hash-password

help:
	@echo ""
	@echo "  Engineer Family – make targets"
	@echo ""
	@echo "  Local dev (no Docker):"
	@echo "    run-siddharth    Run Flask app locally on :5000"
	@echo "    run-suryan       Run Streamlit app locally on :8501"
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
	@echo ""
	@echo "  Utilities:"
	@echo "    shell-siddharth  Open shell in siddharth container"
	@echo "    shell-suryan     Open shell in Streamlit container"
	@echo "    hash-password    Generate a Caddy basicauth hash"
	@echo ""

# ─── Local dev ───────────────────────────────────────────
# Each service has its own venv at services/<name>/.venv
# First time: cd services/siddharth && python -m venv .venv && pip install -r requirements.txt

run-siddharth:
	cd services/siddharth && \
	  . .venv/bin/activate && \
	  FLASK_ENV=development FLASK_DEBUG=1 flask run --port 5000

run-suryan:
	cd services/suryan && \
	  . .venv/bin/activate && \
	  streamlit run app.py --server.port 8501

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
	git tag v$(v)-preprod
	git push origin v$(v)-preprod
	@echo "→ Deploying v$(v)-preprod to preprod..."

tag-prod:
	@test -n "$(v)" || (echo "Usage: make tag-prod v=1.2.3" && exit 1)
	git tag v$(v)
	git push origin v$(v)
	@echo "→ Deploying v$(v) to production..."

# ─── Shells ──────────────────────────────────────────────
shell-siddharth:
	docker compose exec siddharth /bin/bash

shell-suryan:
	docker compose exec suryan /bin/bash

# ─── Utilities ───────────────────────────────────────────
hash-password:
	@read -p "Password: " pw; \
	docker run --rm caddy:2-alpine caddy hash-password --plaintext "$$pw"


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

# ─── Shells ──────────────────────────────────────────────
shell-siddharth:
	docker compose exec siddharth /bin/bash

shell-suryan:
	docker compose exec suryan /bin/bash

# ─── Utilities ───────────────────────────────────────────
hash-password:
	@read -p "Password: " pw; \
	docker run --rm caddy:2-alpine caddy hash-password --plaintext "$$pw"