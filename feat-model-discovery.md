# feat: OpenCode v2 auto-discovery of Ollama models

## Summary

OpenCode could only use the single model named in `.env` (`OLLAMA_MODEL`); other models
already pulled into the `ollama-models` volume did not appear in the TUI. This was because
the installed OpenCode v1 relies on a static `models` map in `config/opencode.json` for
custom providers and does not discover models from Ollama's API.

This change upgrades OpenCode to **v2**, whose built-in `opencode.provider.ollama` plugin
auto-discovers every model pulled into Ollama, and migrates the config to the v2 schema.
The `.env` model remains the default.

## Changes

- `Dockerfile` — install script URL changed from `https://opencode.ai/install` (v1) to
  `https://opencode.ai/v2/install` (v2). Binary still lands at the same in-image path, so
  the `COPY`/`chmod` lines are unchanged. Not version-pinned (tracks latest v2).
- `config/opencode.json` — migrated to the v2 shape: replaced `provider` + `options`/`npm`
  with `providers` + `settings.baseURL`, and removed the manual `models` map so discovery
  populates the picker. Default stays `ollama/{env:OLLAMA_MODEL}`.
- `README.md` — noted the OpenCode v2 upgrade and clarified `OLLAMA_MODEL` is the default
  (switch with `/models`).
- `AGENTS.md` — documented the v2 config shape and that models are auto-discovered, not
  listed in config; added a rule that agents must never write to `TODO.md`.

## Potential issues / risks

- OpenCode v2 is a major version; the TUI and some behaviors/config may differ from v1.
- The v2 binary is native (vs v1's bundled build) and may require additional runtime
  libraries. If the container fails to launch, add the missing packages to the final stage.
- The `opencode` container uses a read-only root filesystem with tmpfs for `~/.local`,
  `~/.config`, and `~/.cache`. v2 may need more space or additional writable paths; if
  `EROFS`/ENOSPC errors appear, add or enlarge tmpfs mounts in `docker-compose.yml`.
- Auto-discovery uses the native Ollama API at `http://ollama:11434` (derived from the `/v1`
  baseURL). If `ollama` is unreachable at startup, no models will be listed.
- Ollama's default context window (`num_ctx`) may be below OpenCode's 64k expectation,
  which can degrade or break tool calls; consider raising it in Ollama.
- `.env` contains an inline comment on the `OLLAMA_MODEL` line; verify the resolved default
  is the clean model tag with no trailing text.
- Removing the manual `models` map means the picker depends entirely on discovery; if
  discovery regresses, re-add explicit entries as a fallback.

## Test plan / verification (manual)

1. `make rebuild` (required: Dockerfile changed).
2. Launch the TUI with `make contagent`.
3. Run `/models` and confirm `qwen3.8:27b`, `qwen3-coder:30b`, and any models added later
   via `ollama pull` all appear.
4. Confirm the default model on session start matches `OLLAMA_MODEL` from `.env`.
5. Select a non-default model in `/models` and confirm a request succeeds.
6. Check `docker compose logs opencode` for config/permission/discovery errors.
7. Note: `make prune` still deletes the `ollama-models` volume and all downloaded models.

## Follow-ups

- Optionally pin the OpenCode v2 version for reproducible builds.
- Document how to change the default model (`.env` + `make rebuild`).
