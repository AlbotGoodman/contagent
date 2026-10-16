.PHONY: build up down model init contagent contagent-gvisor opencode ollama logs prune \
       rebuild reboot audit help _check_env_file _quiet_model

# Default target
.DEFAULT_GOAL := help

# --------------------------------------------------------------------
# Helper to extract a variable from .env at runtime within a recipe
# (ignores comments, strips quotes)
# Usage in recipes: $$(awk '/^[[:space:]]*OLLAMA_MODEL/{print $$2; exit}' .env | tr -d '"')
# --------------------------------------------------------------------
_extract_env = $$(awk '/^[[:space:]]*$(1)/{print $$2; exit}' $(abspath .env))

# --------------------------------------------------------------------
# Help message
# --------------------------------------------------------------------
help:                                   # Show this help message
	@echo "Contagent — Dockerised agentic coding setup"
	@echo ""
	@echo "Quick start:"
	@echo "  make init                 Build, start, and pull model"
	@echo "  make contagent            Launch OpenCode TUI"
	@echo "  make contagent-gvisor     Launch OpenCode TUI under gVisor (needs runsc)"
	@echo ""
	@echo "Lifecycle:"
	@echo "  make build                Build Docker images"
	@echo "  make up                   Start containers (detached)"
	@echo "  make down                 Stop containers"
	@echo "  make rebuild              Rebuild Docker images after changes"
	@echo "  make reboot               Restart containers after compose changes"
	@echo ""
	@echo "Model management:"
	@echo "  make model                Pull Ollama model from .env"
	@echo ""
	@echo "Container access:"
	@echo "  make opencode             Launch OpenCode container (bash)"
	@echo "  make ollama               Enter Ollama container (bash)"
	@echo ""
	@echo "Security:"
	@echo "  make audit                Run recon-leak audit inside the agent container"
	@echo ""
	@echo "Maintenance:"
	@echo "  make prune                Remove everything (containers + volumes)"
	@echo "  make logs                 Tail container logs"

# --------------------------------------------------------------------
# Docker helpers
# --------------------------------------------------------------------
build:                                  # Build Docker images
	docker compose build

up:                                     # Start containers in background
	docker compose up -d

down:                                   # Stop and remove containers
	docker compose down

# --------------------------------------------------------------------
# Model handling
# --------------------------------------------------------------------
model: _check_env_file _quiet_model     # Pull Ollama model from .env

_quiet_model:                           # Pull the configured Ollama model (internal)
	@MODEL=$(_extract_env OLLAMA_MODEL); \
	if [ -z "$$MODEL" ]; then MODEL=qwen3-coder:30b; fi; \
	echo "Pulling Ollama model: $$MODEL"; \
	docker compose exec ollama ollama pull "$$MODEL"

# --------------------------------------------------------------------
# Initialization (full setup)
# --------------------------------------------------------------------
init: _check_env_file up build           # Run checks, start containers, build images
	@echo ""
	@echo "Starting Ollama model pull..."
	$(MAKE) _quiet_model
	@echo "Done. Run 'make contagent' to start the agent."
	@echo ""

# --------------------------------------------------------------------
# Internal sanity check
# --------------------------------------------------------------------
_check_env_file:                         # Verify that .env exists
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found."; \
		echo "Run: cp .env.example .env"; \
		exit 1; \
	fi

# --------------------------------------------------------------------
# Container interaction
# --------------------------------------------------------------------
contagent:                               # Launch OpenCode TUI inside agent container
	@echo "Launching OpenCode TUI..."
	docker compose exec opencode /bin/bash -lc "exec opencode"

contagent-gvisor:                        # Launch OpenCode TUI under gVisor (runsc)
	@command -v runsc >/dev/null 2>&1 || { \
		echo "Error: runsc (gVisor) not found on this host."; \
		echo "Manual install steps: see feat-hardening.md (section 5)."; \
		exit 1; }
	@echo "Launching OpenCode TUI (gVisor)..."
	docker compose -f docker-compose.yml -f docker-compose.gvisor.yml up -d opencode
	docker compose -f docker-compose.yml -f docker-compose.gvisor.yml exec opencode /bin/bash -lc "exec opencode"

audit:                                   # Recon-leak audit inside the agent container
	@docker compose exec opencode bash /workspace/scripts/audit-recon.sh

opencode:                                # Enter the opencode container
	docker compose exec opencode /bin/bash

ollama:                                  # Enter the ollama container
	docker compose exec ollama /bin/bash

logs:                                    # Follow logs for all services
	docker compose logs -f --tail=100

prune:                                   # Remove everything (containers + volumes)
	@docker compose down -v

rebuild:                                 # Rebuild images and start containers
	@docker compose up -d --build

reboot:                                  # Restart after making changes to compose file
	@docker compose down && docker compose up -d && \
	 docker compose exec opencode /bin/bash -lc "exec opencode"
