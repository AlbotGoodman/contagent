.PHONY: build up down shell opencode ollama model pull-model init run clean prune help logs attach-restart _check_env_file

.DEFAULT_GOAL := help

# Extract a variable from .env at runtime within a recipe (ignores comments, strips quotes)
# Usage in recipes: $$(awk '/^[[:space:]]*OLLAMA_MODEL/{print $$2; exit}' .env | tr -d '"')
_extract_env = $$(awk '/^[[:space:]]*$(1)/{print $$2; exit}' $(abspath .env))

help: # Show this help message
	@echo "Contagent — Dockerized agentic coding setup"
	@echo ""
	@echo "Quick start:"
	@echo "  make init      Build, start, and pull model (replaces 'make setup')"
	@echo "  make shell     Enter agent container (bash)"
	@echo "  make opencode  Launch OpenCode TUI agent"
	@echo "  make run       One-liner: init + open opencode"
	@echo ""
	@echo "Lifecycle:"
	@echo "  make build            Build Docker images"
	@echo "  make up               Start containers (detached)"
	@echo "  make down             Stop containers"
	@echo ""
	@echo "Model management:"
	@echo "  make model            Pull Ollama model from .env"
	@echo "  make pull-model       Alias for 'model'"
	@echo ""
	@echo "Agent access:"
	@echo "  make shell     Enter agent container (bash)"
	@echo "  make opencode  Launch OpenCode TUI inside agent container"
	@echo "  make ollama    Enter ollama container (bash)"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean       Stop containers, keep volumes"
	@echo "  make prune       Remove everything (containers + volumes)"
	@echo "  make logs        Tail container logs"
	@echo "  make attach-restart Restart agent and keep opencode running"

build: # Build Docker images
	docker compose build

up: # Start containers in background
	docker compose up -d

down: # Stop and remove containers
	docker compose down

model: _check_env_file
	@MODEL=$(_extract_env OLLAMA_MODEL); \
	if [ -z "$$MODEL" ]; then MODEL=mistral-small; fi; \
	echo "Pulling Ollama model: $$MODEL"; \
	docker compose exec ollama ollama pull "$$MODEL"

pull-model: model

init: _check_env_file up build
	@echo ""
	@echo "Starting Ollama model pull..."
	$(MAKE) _quiet_model
	@echo "Done. Run 'make shell' for bash or 'make opencode' to start the agent."
	@echo ""

# Pull model silently (with fallback) unless already pulled
_quiet_model:
	@MODEL=$(_extract_env OLLAMA_MODEL); \
	if [ -z "$$MODEL" ]; then MODEL=mistral-small; fi; \
	if ! docker compose exec ollama ollama list 2>/dev/null | grep -qw "$$MODEL"; then \
		docker compose exec ollama ollama pull "$$MODEL" > /dev/null 2>&1 && \
		echo "Model $$MODEL pulled." || echo "Warning: failed to pull model."; \
	fi

setup: init
	@echo "(alias for 'init')"

# Check that .env exists (internal use only)
_check_env_file:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found."; \
		echo "Run: cp .env.example .env"; \
		exit 1; \
	fi

opencode: up # Launch OpenCode TUI inside agent container
	@echo "Launching OpenCode TUI..."
	docker compose exec agent /bin/bash -lc "exec opencode"

shell: up # Drop into agent shell
	docker compose exec agent /bin/bash

ollama: up # Enter the ollama container
	docker compose exec ollama /bin/bash

run: _check_env_file init opencode
	@echo ""

logs: # Follow logs for all services
	docker compose logs -f --tail=100

attach-restart: # Restart agent and keep running opencode
	@(docker compose ps -q agent | grep -q . && docker compose restart agent || true) > /dev/null 2>&1
	docker compose exec agent sh -c 'while true; do opencode "${OPENCODE_MODE:-agentic}"; sleep 1; done'

clean: down # Stop containers, keep volumes

prune: # Remove everything (containers + volumes)
	@docker compose down -v
	@docker volume prune -f
