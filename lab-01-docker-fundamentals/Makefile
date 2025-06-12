.PHONY: build run stop logs test clean

IMAGE_NAME := lab01-flask-app
COMPOSE := docker compose

build:
	$(COMPOSE) build

run:
	$(COMPOSE) up -d

stop:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

test:
	@echo "Running smoke test..."
	@sleep 2
	@curl -sf http://localhost:5000/health | python3 -m json.tool && echo "\nHealth check passed!" || echo "\nHealth check failed!"
	@curl -sf http://localhost:5000/api/items | python3 -m json.tool && echo "\nItems endpoint OK" || echo "\nItems endpoint failed"

clean:
	$(COMPOSE) down -v --rmi local --remove-orphans
	docker image prune -f
