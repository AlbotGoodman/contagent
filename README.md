# Contagent

> **Work in progress.** This project is not yet stable. Use it at your own risk and expect breaking changes.

A hardened, Docker-based environment for AI-assisted coding with OpenCode and Ollama running locally on a GPU. All computation stays on your machine — no cloud APIs, no telemetry.

> Only tested on **Linux** with an **NVIDIA RTX 4090**. Setup may require adjustment on other platforms.

## Architecture

Three containers work together. Every model request is routed through Headroom:

```
opencode ──► headroom ──► ollama
           :8787/v1      :8787        :11434
```

- **opencode** — Runs [OpenCode](https://github.com/anomalyco/opencode), a terminal-based coding agent. It has read-only filesystem layers, dropped capabilities, and resource limits for security.
- **headroom** — A context compression proxy sitting between the agent and the model. It compresses tool output, logs and prose before those tokens reach the LLM, then forwards the request upstream. It runs entirely on your machine, and its Kompress model runs on your GPU via PyTorch/CUDA.
- **ollama** — Serves a local LLM ([Ollama](https://ollama.com/)) so your code assistant works offline with zero API keys.

## Prerequisites

- [Docker Engine](https://docs.docker.com/get-docker/) (with Docker Compose v2)
- NVIDIA GPU (compute capability 5.0+)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- 16+ GB RAM, 15+ GB free disk space (the Headroom image with torch/CUDA is ~3 GB larger than the upstream one)
- Linux or macOS (Windows WSL2 also supported)

## Quick Start

```bash
# 1. Clone and enter the repo
git clone <your-repo-url> contagent && cd contagent

# 2. Set up your environment config
cp .env.example .env

# 3. Build, start containers, and pull your model
make init

make contagent

# 4b. Or open a bash shell inside the opencode container
make opencode

Ctrl + D        # Exit the TUI or shell
make down       # Stop containers (your volumes are preserved)
```

> **Pick a model:** Set `OLLAMA_MODEL` in `.env` before running `make init`. Run `docker compose exec ollama ollama list` to see which models you've already downloaded, or browse [ollama.com/library](https://ollama.com/library) for available options.
>
> **Set the context length too:** `OLLAMA_CONTEXT_LENGTH` in `.env` must match `limit.context` in `config/opencode.json`. OpenCode trusts that number when deciding how much room is left before it compacts, so if the two disagree the agent either compacts far too early or overflows the real window.

## Command Reference

| Target | What it does |
|---|---|
| `make help` | Show all available commands |
| **Setup** | |
| `make build` | Build Docker images |
| `make up` | Start containers in the background |
| `make down` | Stop and remove containers |
| `make init` | Build, start, and pull the model (full setup) |
| `make model` | Pull the Ollama model named in `.env` |
| **Interact** | |
| `make contagent` | Launch the OpenCode coding agent TUI |
| `make opencode` | Open a bash shell inside the opencode container |
| `make ollama` | Open a bash shell inside the Ollama container |
| `make headroom` | Open a bash shell inside the Headroom container |
| `make logs` | Follow container logs in real-time |
| **Maintenance** | |
| `make rebuild` | Rebuild images after Dockerfile changes and restart |
| `make reboot` | Restart after docker-compose.yml changes |
| `make prune` | Remove everything — containers, volumes, and cached models |

## Configuration

The `config/` directory holds OpenCode's configuration. It is mounted as a writable volume so your customizations persist across runs. Edit files in `config/` while the containers are stopped or after exiting the TUI.

## Headroom Context Compression

[Headroom](https://github.com/headroomlabs-ai/headroom) is a context compression proxy. The agent's requests pass through it, tool outputs and logs are compressed before the tokens reach the model, and the request is then forwarded to Ollama. No code changes are needed in your project.

### How it is wired

OpenCode is pointed at Headroom rather than at Ollama directly. The provider block in `config/opencode.json` sets `baseURL` to `http://headroom:8787/v1`, and the `headroom` service in `docker-compose.yml` is told where to forward to via `OPENAI_TARGET_API_URL=http://ollama:11434/v1`. That `/v1` suffix is required — it is Ollama's OpenAI-compatible endpoint.

### What actually gets compressed

Headroom detects the content type of each block and picks a compressor:

| Content type | Compressor |
|---|---|
| JSON | Statistical crushing — keeps errors and anomalies, drops repetition |
| Source code | AST-aware — keeps signatures, collapses bodies |
| Prose, logs, diffs | Kompress, a ModernBERT model scoring each token for retention |

### Kompress runs on the GPU, via PyTorch/CUDA

Kompress has two interchangeable engines: ONNX Runtime (CPU) and PyTorch. The published Headroom image ships only the ONNX path (the `proxy` extra) and no torch, so this repo builds a derived image — `Dockerfile.headroom` — which installs the upstream `ml` extra (torch, transformers, huggingface-hub) on top of `ghcr.io/headroomlabs-ai/headroom:latest`. Three things make the GPU path active:

- `docker-compose.yml` builds `contagent-headroom:latest` from that Dockerfile and gives the service the same `nvidia` GPU reservation Ollama uses. Without the reservation the container cannot see the card and torch silently falls back to CPU.
- `HEADROOM_KOMPRESS_BACKEND=pytorch` forces the PyTorch engine. It has to be forced: the default `auto` always tries ONNX first and would never reach torch. Once the GPU is visible, Headroom's `device=auto` resolves to `cuda` on its own — there is no separate device setting.
- The service's memory limit was raised from 2 GB to 4 GB; torch plus the CUDA context needs more resident memory than ONNX did.

Verify it after `make rebuild`:

```bash
docker compose exec headroom python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
docker compose logs headroom | grep -i "Kompress PyTorch"    # expect: loaded on cuda ...
```

Two things follow from the first-use download, and they are the most common source of confusion:

- **The first request is slow.** The Kompress weights (several hundred MB, pulled from HuggingFace) download on first use. They are cached in the `headroom-models` volume so this happens once rather than on every restart. Watch `docker compose logs headroom` on the very first run. `Dockerfile.headroom` gives `/headroom-cache` nonroot ownership so the volume is seeded correctly — if the volume predates that change, delete just that volume once (`docker volume ls -q | grep headroom-models`, then `docker volume rm …`) and let it re-download.
- **Tiny prompts show 0% savings.** Kompress passes messages under roughly ten words through untouched. Savings only appear on context-heavy turns.

Expect meaningfully smaller reductions than Headroom's headline figures. Those numbers are dominated by JSON, which a coding agent produces less of than a data pipeline does. On representative coding traffic the maintainers report roughly 28%.

**If VRAM gets tight**, Ollama's model runner and Kompress now share the card. Should Ollama start dropping its model (see `TODO.md`), flip `HEADROOM_KOMPRESS_BACKEND` back to `onnx_cpu` in `docker-compose.yml` — the ONNX runtime stays installed in the image, so it is a one-line revert — or free VRAM by using a smaller Ollama model.

To run the structural compressors only and skip Kompress entirely, add `HEADROOM_DISABLE_KOMPRESS=1` to the `headroom` service.

### A note on `apiKey` in the config

`config/opencode.json` contains `"apiKey": "unused"`. This is a deliberate placeholder, not a secret. OpenCode refuses to dispatch a request against a custom provider unless it can resolve a credential, and the usual source — `auth.json` — lives under `/home/superuser/.local`, which is a tmpfs here and therefore wiped on every restart. Headroom ignores the inbound `Authorization` header when routing, and Ollama does not authenticate. Removing the line brings back the `missing API key` error.

## Security Highlights

- Agent and Headroom containers run as non-root users
- Read-only root filesystem with tmpfs for necessary temp directories
- All Linux capabilities dropped (`cap_drop: ALL`)
- No privilege escalation allowed
- Resource limits: 4 GB RAM per container (2 CPUs for opencode/ollama, 1 CPU for headroom)
- Ollama's published port is bound to `127.0.0.1` only
- No prompt, file content or conversation state is persisted between restarts

## Threat Model

Contagent hardens the **runtime** environment — if an agent or a dependency escapes its sandbox, the damage surface is narrow. However, some risks are inherent to the design and cannot be mitigated without changing what this tool does:

- **Code execution is the point.** The agent runs arbitrary code (shell commands, scripts, package installs) inside the agent container with access to your workspace files via a volume mount. A compromised model or malicious command can modify or exfiltrate host data that is bind-mounted into the container.
- **Host port exposure.** Ollama's port `11434` and Headroom's port `8787` are both bound to `127.0.0.1`, so they are reachable only from this machine. Keep it that way — anyone who reaches the proxy can infer prompts, read model output, and influence the agent's behavior.
- **The headroom service runs as a non-root user.** The published Headroom image defaults to a `nonroot` user and `Dockerfile.headroom` keeps it — it escalates to root only during the build to install torch. The container holds no secrets and no persistent user data beyond a writable model cache. Confirm with `docker compose exec headroom id`.
- **Egress on first run.** The Kompress weights are fetched from `huggingface.co` the first time the proxy compresses something. Afterwards the cache is warm and nothing further is downloaded. To guarantee no egress at all, run it once, then add `HF_HUB_OFFLINE=1` to the `headroom` service.
- **Shared volume persistence.** `make prune` removes all volumes, including `ollama-models` (your downloaded models) and `headroom-models` (the Kompress weights) — expect a long re-pull afterwards. Neither volume contains prompts or file content; all conversation state lives on a tmpfs and is already gone by then.
- **Resource exhaustion (GPU).** Running large models alongside the agent can fill GPU VRAM, causing OOM kills that corrupt model state. Monitor your GPU usage and keep a headroom of 2–4 GB free. Ollama (inference) and Headroom (Kompress compression) now both use the GPU; if Ollama's model runner starts crashing, set `HEADROOM_KOMPRESS_BACKEND=onnx_cpu` to move compression back to the CPU.

## License

MIT — see `LICENSE` for details.
