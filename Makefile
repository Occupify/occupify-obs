.PHONY: all up down restart logs verify status deploy-web deploy-agents expose-db

all: up

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

status:
	docker compose ps

verify:
	bash scripts/verify-all.sh

deploy-web:
	bash scripts/deploy-web.sh

deploy-agents:
	bash scripts/deploy-agents.sh

expose-db:
	bash scripts/expose-databases.sh
