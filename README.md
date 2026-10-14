# Contagent

A hardened, Docker-based environment for AI-assisted coding using
[OpenCode](https://opencode.ai) with a local [Ollama](https://ollama.com/) model on
your own NVIDIA GPU. No cloud APIs and no API keys — inference stays on your machine.

> Tested on Linux with an NVIDIA RTX 4090. An NVIDIA GPU is required; macOS is not
> supported because Docker cannot pass a GPU through on Apple hardware.

## Architecture

Two containers work together on the `agent-network` bridge:

| Service    | Container            | Role                                             |
| ---------- | -------------------- | ------------------------------------------------ |
| `opencode` | `contagent-opencode` | [OpenCode](https://opencode.ai) coding agent TUI |
| `ollama`   | `contagent-ollama`   | Local LLM inference on the GPU                   |

Ollama is published only on `127.0.0.1:11434` (loopback), so it is reachable from the
host but not from other machines on the network.

### Mounts and volumes

- `./` → `/workspace` (rw) — the project the agent edits
- `./config` → `/home/superuser/.config/opencode` (rw) — OpenCode config, persists across runs
- `ollama-models` volume → `/root/.ollama` — downloaded models

## Requirements

- [Docker Engine](https://docs.docker.com/get-docker/) with Docker Compose v2
- An NVIDIA GPU (compute capability 5.0+) and the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- ~16 GB RAM and ~25 GB free disk space
- Linux with NVIDIA drivers

## Quick Start

```bash
# 1. Clone and enter the repo
git clone https://github.com/albotgoodman/contagent.git && cd contagent

# 2. Set up your environment config
cp .env.example .env

# 3. Check .env, start the containers, and pull the model
make init

# 4. Launch the OpenCode agent TUI
make contagent
```

## Usage Guide

Contagent is driven through Makefile commands:

1. Run `make help` to see all available commands
2. Use `make init` to check `.env`, start the containers, and pull the model
3. Run `make contagent` to launch the OpenCode TUI for coding tasks
4. Use `make down` to stop containers when finished

The `config/` directory holds OpenCode's configuration. It is mounted as a writable
volume so your customizations persist across runs. Edit files in `config/` while the
containers are stopped or after exiting the TUI.

## Configuration

Copy `.env.example` to `.env` and adjust as needed:

| Variable        | Default                  | Purpose                                       |
| --------------- | ------------------------ | --------------------------------------------- |
| `OLLAMA_MODEL`  | `qwen3-coder:30b`        | Model pulled by `make init` and used by OpenCode |
| `OLLAMA_HOST`   | `http://localhost:11434` | Ollama endpoint (host side)                   |
| `OPENCODE_MODE` | `agentic`                | Passed into the opencode container            |
| `HOST_UID`      | `1000`                   | UID the container user runs as                |
| `HOST_GID`      | `1000`                   | GID the container user runs as                |

## Security Highlights

- Agent container runs as a non-root user
- Read-only root filesystem with tmpfs for necessary temp directories
- All Linux capabilities dropped (`cap_drop: ALL`)
- No privilege escalation allowed (`no-new-privileges:true`)
- Resource limits: 2 CPUs, 4 GB RAM per container

## Threat Model

Contagent hardens the **runtime** environment — if an agent or a dependency escapes
its sandbox, the damage surface is narrow. However, some risks are inherent to the
design and cannot be mitigated without changing what this tool does:

- **Code execution is the point.** The agent runs arbitrary code (shell commands,
  scripts, package installs) inside the agent container with access to your workspace
  files via a read-write bind mount. A compromised model or malicious command can
  modify or exfiltrate host data that is bind-mounted into the container.
- **Local-only Ollama port.** Ollama is bound to `127.0.0.1:11434`, so it is not
  reachable from other hosts. Keep it that way — if you widen the binding, anyone who
  reaches it can infer prompts and read model outputs.
- **Shared volume persistence.** Models are stored in the `ollama-models` Docker
  volume (`contagent_ollama-models`). `make prune` (`docker compose down -v`) deletes
  this volume and wipes downloaded models. To reclaim space deliberately, run
  `docker volume rm contagent_ollama-models`.
- **Resource exhaustion (GPU).** Running large models alongside the agent can fill GPU
  VRAM, causing OOM kills that corrupt model state. Monitor your GPU usage and keep a
  headroom of 2–4 GB free.
- **Model provenance.** The `ollama/ollama:latest` image is unpinned; pin a version if
  you need reproducible setups.

## License

Released under the MIT License. See [LICENSE](LICENSE).
