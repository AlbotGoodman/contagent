.PHONY: build up down shell agent ollama model pull-model init run clean prune help logs attach-restart _check_env_file

.DEFAULT_GOAL := help

# Extract a variable from .env at runtime within a recipe (ignores comments, strips quotes)
# Usage in recipes: $$(awk '/^[[:space:]]*OLLAMA_MODEL/{print $$2; exit}' .env | tr -d '"')
_extract_env = $$(awk '/^[[:space:]]*$(1)/{print $$2; exit}' $(abspath .env))

help: # Show this help message
	@echo "Contagent — Dockerized agentic coding setup"
	@echo ""
	@echo "Quick start:"
	@echo "  make init   		   Build, start, and pull model"
	@echo "  make agent   		   Launch OpenCode TUI agent"
	@echo "  make run     		   One-liner: init + launch agent"
	@echo ""
	@echo "Lifecycle:"
	@echo "  make build            Build Docker images"
	@echo "  make up               Start containers (detached)"
	@echo "  make down             Stop containers"
	@echo ""
	@echo "Model management:"
	@echo "  make model            Pull Ollama model from .env"
	@echo ""
	@echo "Agent access:"
	@echo "  make agent   		   Launch OpenCode TUI inside agent container"
	@echo "  make ollama   		   Enter ollama container (bash)"
	@echo ""
	@echo "Maintenance:"
	@echo "  make prune    		   Remove everything (containers + volumes)"
	@echo "  make logs     		   Tail container logs"
	@echo "  make attach-restart   Restart agent and keep opencode running"

build: # Build Docker images
	docker compose build

up: # Start containers in background
	docker compose up -d

down: # Stop and remove containers
	docker compose down

model: _check_env_file
	@MODEL=$(_extract_env OLLAMA_MODEL); \
	if [ -z "$$MODEL" ]; then MODEL=qwen3-coder:30b; fi; \
	echo "Pulling Ollama model: $$MODEL"; \
	docker compose exec ollama ollama pull "$$MODEL"

init: _check_env_file up build
	@echo ""
	@echo "Starting Ollama model pull..."
	$(MAKE) _quiet_model
	@echo "Done. Run 'make shell' for bash or 'make agent' to start the agent."
	@echo ""

# Pull model silently (with fallback) unless already pulled
_quiet_model:
	@MODEL=$(_extract_env OLLAMA_MODEL); \
	if [ -z "$$MODEL" ]; then MODEL=qwen3-coder:30b; fi; \
	if ! docker compose exec ollama ollama list 2>/dev/null | grep -qw "$$MODEL"; then \
		docker compose exec ollama ollama pull "$$MODEL" > /dev/null 2>&1 && \
		echo "Model $$MODEL pulled." || echo "Warning: failed to pull model."; \
	fi

# Check that .env exists (internal use only)
_check_env_file:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found."; \
		echo "Run: cp .env.example .env"; \
		exit 1; \
	fi

agent: up # Launch OpenCode TUI inside agent container
	@echo "Launching OpenCode TUI..."
	docker compose exec agent /bin/bash -lc "exec opencode"

ollama: up # Enter the ollama container
	docker compose exec ollama /bin/bash

run: _check_env_file init agent
	@echo ""

logs: # Follow logs for all services
	docker compose logs -f --tail=100

attach-restart: # Restart agent and keep running opencode
	@(docker compose ps -q agent | grep -q . && docker compose restart agent || true) > /dev/null 2>&1
	docker compose exec agent sh -c 'while true; do opencode "${OPENCODE_MODE:-agentic}"; sleep 1; done'

prune: # Remove everything (containers + volumes)
	@docker compose down -v

rebuild: # Rebuilds the images and start container in the background
	@docker compose up -d --build