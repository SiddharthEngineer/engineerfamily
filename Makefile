# Makefile – common dev and deploy helpers
# Usage: make <target>

.PHONY: help up down logs ps build restart shell-siddharth shell-suryan \
        preprod-up preprod-down hash-password

help:
	@echo ""
	@echo "  Engineer Family – make targets"
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
	@echo "  Utilities:"
	@echo "    shell-siddharth  Open shell in Django container"
	@echo "    shell-suryan     Open shell in Streamlit container"
	@echo "    hash-password    Generate a Caddy basicauth hash (prompts for password)"
	@echo ""

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
