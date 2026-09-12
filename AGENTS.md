# Contagent — AGENTS.md

This repo is a Docker template/scaffold, not an application. All source files are infra: `Dockerfile`, `docker-compose.yml`, the Makefile, and `config/opencode.json`. Treat everything else (`.env`, README, PLAN.md) as documentation.

## Development conventions
- **No scripts or app code.** If you add any shell scripts, put them in a `scripts/` directory — keep the root clean.
- **Makefile targets are public API.** Every new feature needs a matching `make` target and a README line describing it. Follow the existing style: `.PHONY`, `_internal:` helpers, `$$(awk ...)` env extraction with `$$` escaping.
- **docker-compose.yml is the architecture source of truth.** All service definitions, resource limits, volumes, networks, and port mappings live here. Changes to how containers interact (new services, new mounts, networking) go here.
- **`.env.example` is a user contract.** Every variable it declares must exist for `make init` to work end-to-end. Document each one with a comment. Delete any that are no longer used.
- **Config overrides:** `config/opencode.json` only configures the OpenCode provider (Ollama baseURL and model list). Never put runtime env var defaults here — `.env` and compose are the sources of truth.

## Verification
- After changing anything, run `make init` from scratch to verify end-to-end: clean start → containers running → model pulled → `docker compose exec agent opencode` usable.
- After changing docker-compose.yml, run `docker compose config` to validate syntax.
- After changing the Dockerfile, run `make build && make shell` to verify the container starts and `superuser` has correct permissions.

## Gotchas
- **`.env` is gitignored.** Agents shouldn't assume it exists during development — `.env.example` drives all work. If a new variable is needed, add it to both files.
- **Plan.md contains Open Decision Points that block implementation** with Do-Not-Do rules. Read it before making changes.
