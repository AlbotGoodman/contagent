.PHONY: build up down shell agent ollama model pull-model init run clean prune help logs attach-restart _check_env_file

.DEFAULT_GOAL := help

# Extract a variable from .env at runtime within a recipe (ignores comments, strips quotes)
# Usage in recipes: $$(awk '/^[[:space:]]*OLLAMA_MODEL/{print $$2; exit}' .env | tr -d '"')
_extract_env = $$(awk '/^[[:space:]]*$(1)/{print $$2; exit}' $(abspath .env))

help: # Show this help message
	@echo "Contagent — Dockerised agentic coding setup"
	@echo ""
	@echo "Quick start:"
	@echo "  make init   		   Build, start, and pull model"
	@echo "  make contagent   	   Launch OpenCode TUI"
	@echo ""
	@echo "Lifecycle:"
	@echo "  make build            Build Docker images"
	@echo "  make up               Start containers (detached)"
	@echo "  make down             Stop containers"
	@echo "  make rebuild          Rebuild Docker images after changes to Dockerfile"
	@echo "  make reboot           Restart containers after changes to compose file"
	@echo ""
	@echo "Model management:"
	@echo "  make model            Pull Ollama model from .env"
	@echo ""
	@echo "Container access:"
	@echo "  make opencode   	   Launch OpenCode container (bash)"
	@echo "  make ollama   		   Enter Ollama container (bash)"
	@echo ""
	@echo "Maintenance:"
	@echo "  make prune    		   Remove everything (containers + volumes)"
	@echo "  make logs     		   Tail container logs"


build: # Build Docker images
	docker compose build

up: # Start containers in background
	docker compose up -d

down: # Stop and remove containers
	docker compose down

model: 
	_check_env_file
	@MODEL=$(_extract_env OLLAMA_MODEL); \
	if [ -z "$$MODEL" ]; then MODEL=qwen3-coder:30b; fi; \
	echo "Pulling Ollama model: $$MODEL"; \
	docker compose exec ollama ollama pull "$$MODEL"

init: # Setup Contagent with images, containers and models
	_check_env_file up build 
	@echo ""
	@echo "Starting Ollama model pull..."
	$(MAKE) _quiet_model
	@echo "Done. Run 'make contagent' to start the agent."
	@echo ""

_check_env_file: # Check that .env exists (internal use only)
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found."; \
		echo "Run: cp .env.example .env"; \
		exit 1; \
	fi

contagent: # Launch OpenCode TUI inside agent container
	@echo "Launching OpenCode TUI..."
	docker compose exec agent /bin/bash -lc "exec opencode"

opencode: # Enter the opencode container
	docker compose exec opencode /bin/bash

ollama: # Enter the ollama container
	docker compose exec ollama /bin/bash

logs: # Follow logs for all services
	docker compose logs -f --tail=100

prune: # Remove everything (containers + volumes)
	@docker compose down -v

rebuild: # Rebuilds the images and start container in the background
	@docker compose up -d --build

reboot: # Restart after making changes to the compose file
	@docker compose down && docker compose up -d && docker compose exec agent /bin/bash -lc "exec opencode"