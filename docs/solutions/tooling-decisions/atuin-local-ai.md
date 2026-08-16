---
title: "Use Atuin with local Ollama for terminal AI"
date: 2026-07-20
tags: [atuin, ollama, local-ai, zsh, dotfiles]
---

# Use Atuin with local Ollama for terminal AI

## Decision

Use Atuin, Ollama, and a self-hosted `atuin-ai-server` for terminal AI. Keep Ghostty and zsh. Do not use Warp AI for this workflow because Warp does not currently provide a documented local-only LLM path for personal use.

## Local Install

Install tracked mise tools:

```bash
mise install atuin
```

Install Ollama using the platform package or the official Ollama installer. On this Fedora machine, prefer the official installer unless a trusted Fedora package is already configured:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Pull the local models:

```bash
ollama pull qwen3-coder:30b
ollama pull gpt-oss:20b
```

Start or verify Ollama:

```bash
ollama serve
curl --fail --silent --show-error http://localhost:11434/v1/models
```

Deploy the tracked Atuin package from this repo:

```bash
stow -t ~ atuin
```

If the Atuin AI backend service is already enabled, recreate it after configuration changes. Restarting recreates the `--rm` container with the tracked pasta network arguments:

```bash
systemctl --user daemon-reload
systemctl --user enable atuin-ai.service
systemctl --user restart atuin-ai.service
systemctl --user status atuin-ai.service
```

Verify the Atuin AI endpoint:

```bash
curl --fail --silent --show-error http://localhost:8080/api/cli/models | rg 'qwen3-coder-30b|gpt-oss-20b'
```

Open a fresh zsh session and verify Atuin:

```bash
command -v atuin
atuin doctor
```

## Local-Only Guardrails

Tracked Atuin config sets:

- `auto_sync = false`
- `update_check = false`
- `sync_address = "http://127.0.0.1:9"`
- `[ai] endpoint = "http://localhost:8080"`
- `[ai] endpoint_protocol = "oss"`
- `[ai] yolo = false`
- `[ai.capabilities] enable_history_output = false`
- `[ai.capabilities] enable_file_tools = false`
- `[ai.capabilities] enable_command_execution = false`

The AI backend config points only at Ollama:

```toml
endpoint = "http://127.0.0.1:11434/v1"
default_model = "qwen3-coder-30b"
```

The service's `--network=pasta:-T,11434` argument forwards only the container's TCP port 11434 to host loopback. Ollama must remain on `127.0.0.1:11434`; neither host networking nor `OLLAMA_HOST=0.0.0.0:11434` is required.

Do not run `atuin login`, do not enable Atuin Hub sync, and do not replace the endpoint with OpenAI, OpenRouter, Bedrock, or Warp.

## Troubleshooting

Check each boundary in order:

```bash
# Host Ollama: must succeed and remain bound to loopback.
ss -ltn 'sport = :11434'
curl --fail --silent --show-error http://127.0.0.1:11434/v1/models

# Atuin backend and its recent upstream errors.
systemctl --user status atuin-ai.service
journalctl --user-unit atuin-ai.service --no-pager -n 50
curl --fail --silent --show-error http://127.0.0.1:8080/api/cli/models

# End-to-end inference.
atuin ai inline --verbose "echo hello"
```

An `ECONNREFUSED` error for `127.0.0.1:11434` in the container logs means either Ollama is stopped or the service was not restarted with the pasta forwarding argument.

If command generation is slow, switch `[ai] model` in `~/.config/atuin/config.toml` from `qwen3-coder-30b` to `gpt-oss-20b`.

If zsh starts but Atuin history is not recording commands, run:

```bash
atuin doctor
```

Confirm `atuin init zsh --disable-up-arrow` is loaded from `.zshrc` and that the shell is interactive.
