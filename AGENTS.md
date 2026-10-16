# AGENTS.md

## What this repo is
Infrastructure repo (Docker Compose + Makefile), **not** an application. It defines
`contagent`: two containers — `opencode` (the coding agent) and `ollama` (local GPU
inference). There is no source tree, test suite, linter, or typechecker. Verification is
done by running the stack.

## Commands
- `make` / `make help` — list all targets (default goal is `help`).
- `make init` — the real setup: checks `.env`, builds the image, starts containers, pulls the model. Run this first.
- `make contagent` — launch the OpenCode TUI (interactive; needs the stack already up).
- `make opencode` / `make ollama` — shell into each container.
- `make model` — pull the `OLLAMA_MODEL` from `.env`.
- `make rebuild` — rebuild + restart (required after Dockerfile or `.env` UID/GID changes).
- `make reboot` — restart after docker-compose changes.
- `make prune` — `docker compose down -v`; **deletes the `ollama-models` volume and all downloaded models.**
- `make logs` — tail all container logs.

## Setup requirements
- `.env` is required and gitignored; create with `cp .env.example .env`.
- NVIDIA GPU + Container Toolkit required; macOS is unsupported.
- `HOST_UID`/`HOST_GID` are Docker build args baked into the image — changing them needs
  `make rebuild`, not just a restart.

## Wiring facts an agent will otherwise miss
- The repo root is bind-mounted to `/workspace` in the `opencode` container: the agent
  edits the same files you see here, live.
- `config/` is bind-mounted to `/home/superuser/.config/opencode`. `config/opencode.json`
  is the live OpenCode config, not a template.
- Inside containers Ollama is `http://ollama:11434` (see `config/opencode.json`); on the
  host it is `127.0.0.1:11434` (loopback only — keep it that way).
- The `opencode` container runs as non-root with a read-only root filesystem plus tmpfs;
  only `/workspace` and `config/` persist.
- OpenCode is **v2** (installed from `https://opencode.ai/v2/install`).
  `config/opencode.json` uses the v2 shape: `providers` + `settings.baseURL` (not v1's
  `provider` + `options`/`npm`). Models are **not** listed in config — v2 auto-discovers
  every model pulled into Ollama; `.env`'s `OLLAMA_MODEL` is only the default
  (`ollama/{env:OLLAMA_MODEL}`).

## Repo conventions
- **Never write to `TODO.md`.** It is the human's personal session notes; agents must not
  create, edit, or append to it.
- `TODO.md`, `PLAN.md`, and `data/` are gitignored (session notes / backlog). `data/headroom.md`
  is third-party Headroom docs for a planned feature — not project code.
- Work in feature branches and never merge into `master`. 
- Keep security posture in `docker-compose.yml` (`cap_drop: ALL`, `no-new-privileges`,
  `read_only`, resource limits) intact unless the task is explicitly about it.
