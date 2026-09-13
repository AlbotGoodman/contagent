# Contagent

> **Work in progress.** This project is not yet stable. Use it at your own risk and expect breaking changes.

A hardened, Docker-based environment for AI-assisted coding with OpenCode and Ollama running locally on a GPU. All computation stays on your machine — no cloud APIs, no telemetry.

> Only tested on **Linux** with an **NVIDIA RTX 4090**. Setup may require adjustment on other platforms.

## Architecture

Two containers work together:

- **agent** — Runs [OpenCode](https://github.com/nicepkg/opencode), a terminal-based coding agent. It has read-only filesystem layers, dropped capabilities, and resource limits for security.
- **ollama** — Serves a local LLM ([Ollama](https://ollama.com/)) so your code assistant works offline with zero API keys.

## Prerequisites

- [Docker Engine](https://docs.docker.com/get-docker/) (with Docker Compose v2)
- NVIDIA GPU (compute capability 5.0+)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- 16+ GB RAM, 10 GB free disk space
- Linux or macOS (Windows WSL2 also supported)

## Quick Start

```bash
# 1. Clone and enter the repo
git clone <your-repo-url> contagent && cd contagent

# 2. Set up your environment config
cp .env.example .env

# 3. Build, start containers, and pull your model
make init

make agent

# 4b. Or open a bash shell inside the agent container
make shell

Ctrl + D        # Exit the TUI or shell
make down       # Stop containers (your volumes are preserved)
```

> **Pick a model:** Set `OLLAMA_MODEL` in `.env` before running `make init`. Run `docker compose exec ollama ollama list` to see which models you've already downloaded, or browse [ollama.com/library](https://ollama.com/library) for available options.

## Command Reference

| Target | What it does |
|---|---|
| `make help` | Show all available commands |
| **Setup** | |
| `make build` | Build Docker images |
| `make up` | Start containers in the background |
| `make down` | Stop and remove containers |
| `make init` | Build, start, and pull the model (full setup) |
| `make run` | One-liner: `init` + launch OpenCode |
| **Interact** | |
| `make agent` | Launch the OpenCode coding agent TUI |
| `make shell` | Open a bash shell inside the agent container |
| `make ollama` | Open a bash shell inside the Ollama container |
| `make logs` | Follow container logs in real-time |
| **Maintenance** | |
| `make clean` | Stop containers (keeps your data) |
| `make prune` | Remove everything — containers, volumes, and cached images |

## Configuration

The `config/` directory holds OpenCode's configuration. It is mounted as a writable volume so your customizations persist across runs. Edit files in `config/` while the containers are stopped or after exiting the TUI.

## Security Highlights

- Agent container runs as a non-root user
- Read-only root filesystem with tmpfs for necessary temp directories
- All Linux capabilities dropped (`cap_drop: ALL`)
- No privilege escalation allowed
- Resource limits: 2 CPUs, 4 GB RAM per container

## Threat Model

Contagent hardens the **runtime** environment — if an agent or a dependency escapes its sandbox, the damage surface is narrow. However, some risks are inherent to the design and cannot be mitigated without changing what this tool does:

- **Code execution is the point.** The agent runs arbitrary code (shell commands, scripts, package installs) inside the agent container with access to your workspace files via a volume mount. A compromised model or malicious command can modify or exfiltrate host data that is bind-mounted into the container.
- **Host port exposure.** The Ollama port `11434` is exposed on all interfaces. Anyone who reaches it can infer prompts, read model outputs, and potentially influence the agent's behavior. Consider firewalling this port to your local network only.
- **Shared volume persistence.** Models stored in the `ollama-models` Docker volume survive `make prune`. If you decommission or share this machine, manually remove the volume (`docker volume rm contagent_ollama-models`) to wipe downloaded models.
- **Resource exhaustion (GPU).** Running large models alongside the agent can fill GPU VRAM, causing OOM kills that corrupt model state. Monitor your GPU usage and keep a headroom of 2–4 GB free.

## License

MIT — see `LICENSE` for details.
