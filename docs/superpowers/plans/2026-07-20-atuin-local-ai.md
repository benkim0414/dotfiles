# Atuin Local AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a strictly local Atuin AI setup that keeps Ghostty and zsh, runs all LLM inference through local Ollama, and routes Atuin AI through a local `atuin-ai-server`.

**Architecture:** Track Atuin client configuration under `atuin/.config/atuin/config.toml`, Atuin AI backend configuration under `atuin/.config/atuin-ai/config.toml`, and a user systemd service for running the backend with Podman. zsh loads Atuin only when the `atuin` command exists, after mise activation has made shims available. A focused shell test validates that tracked config does not include cloud AI fallback and that dangerous AI capabilities stay disabled.

**Tech Stack:** zsh, mise, Atuin CLI, Atuin AI OSS server, Ollama OpenAI-compatible local endpoint, Podman, systemd user services, Python 3 `tomllib` for config validation.

## Global Constraints

- Strictly local AI only.
- Keep Ghostty and zsh as the terminal foundation.
- Do not install or configure Warp for AI.
- Do not enable Atuin Hub, hosted Atuin AI, OpenAI, OpenRouter, AWS Bedrock, or any cloud fallback.
- Use `qwen3-coder:30b` as the first local model and `gpt-oss:20b` as the fallback model.
- Treat CPU local inference as the reliable baseline; do not depend on ROCm, NPU support, `/dev/kfd`, `/dev/dri`, or NVIDIA.
- Do not enable YOLO-style permission bypass.
- Do not silently execute destructive commands or grant broad file write privileges from Atuin AI.
- Stage explicit paths only and commit each task separately.

---

## File Structure

- Modify `mise/.config/mise/config.toml`: add Atuin CLI to the existing global tool list.
- Modify `zsh/.zshrc`: initialize Atuin after mise activation when `atuin` exists, while preserving existing up-arrow history behavior.
- Create `atuin/.config/atuin/config.toml`: local-only Atuin client and AI endpoint settings.
- Create `atuin/.config/atuin-ai/config.toml`: local Atuin AI backend config pointing at Ollama.
- Create `atuin/.config/systemd/user/atuin-ai.service`: user service to run `atuin-ai-server` through Podman on localhost.
- Create `atuin/tests/local-ai-config/run.sh`: regression checks for local-only endpoints, conservative capabilities, zsh wiring, and service shape.
- Create `docs/solutions/tooling-decisions/atuin-local-ai.md`: operator notes for installing Ollama, pulling local models, enabling the service, and verifying no cloud fallback.

### Task 1: Add Atuin Client Config And zsh Integration

**Files:**
- Modify: `mise/.config/mise/config.toml`
- Modify: `zsh/.zshrc`
- Create: `atuin/.config/atuin/config.toml`
- Create: `atuin/tests/local-ai-config/run.sh`

**Interfaces:**
- Produces: `atuin/.config/atuin/config.toml` with `[ai] endpoint = "http://localhost:8080"` and `endpoint_protocol = "oss"`.
- Produces: zsh startup that runs `eval "$(atuin init zsh --disable-up-arrow)"` only when `atuin` is on `PATH`.
- Consumes: mise activation in `.zshrc`, XDG stow layout, Python 3.11+ `tomllib`.

- [ ] **Step 1: Write the failing config test**

Create `atuin/tests/local-ai-config/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
ATUIN_CONFIG="$ROOT/atuin/.config/atuin/config.toml"
AI_SERVER_CONFIG="$ROOT/atuin/.config/atuin-ai/config.toml"
AI_SERVICE="$ROOT/atuin/.config/systemd/user/atuin-ai.service"
ZSHRC="$ROOT/zsh/.zshrc"
MISE_CONFIG="$ROOT/mise/.config/mise/config.toml"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

ok() {
  printf 'ok %s\n' "$1"
}

python3 - "$ATUIN_CONFIG" <<'PY'
import sys
import tomllib

path = sys.argv[1]
with open(path, "rb") as fh:
    config = tomllib.load(fh)

ai = config.get("ai", {})
capabilities = ai.get("capabilities", {})
opening = ai.get("opening", {})

assert config.get("auto_sync") is False
assert config.get("update_check") is False
assert config.get("sync_address") == "http://127.0.0.1:9"
assert config.get("enter_accept") is False
assert config.get("secrets_filter") is True
assert ai.get("enabled") is True
assert ai.get("endpoint") == "http://localhost:8080"
assert ai.get("endpoint_protocol") == "oss"
assert ai.get("model") == "qwen3-coder-30b"
assert "api_token" not in ai
assert ai.get("yolo") is False
assert capabilities.get("enable_history_search") is True
assert capabilities.get("enable_history_output") is False
assert capabilities.get("enable_file_tools") is False
assert capabilities.get("enable_command_execution") is False
assert opening.get("send_cwd") is True
assert opening.get("send_last_command") is False
PY
ok "Atuin client config is strict local AI"

if rg -n 'api\.atuin\.sh|openai|openrouter|bedrock|warp' "$ATUIN_CONFIG"; then
  fail "Atuin client config contains a cloud or Warp endpoint"
fi
ok "Atuin client config contains no cloud AI endpoint"

rg -q '^atuin = "latest"$' "$MISE_CONFIG" \
  || fail "mise config must install Atuin"
ok "mise installs Atuin"

rg -q 'eval "\$\(atuin init zsh --disable-up-arrow\)"' "$ZSHRC" \
  || fail "zshrc must initialize Atuin without stealing up-arrow"
ok "zsh initializes Atuin conservatively"

if [[ -f "$AI_SERVER_CONFIG" ]]; then
  python3 - "$AI_SERVER_CONFIG" <<'PY'
import sys
import tomllib

path = sys.argv[1]
with open(path, "rb") as fh:
    config = tomllib.load(fh)

assert config.get("port") == 8080
assert config.get("endpoint") == "http://host.containers.internal:11434/v1"
assert config.get("api_key") == "ollama"
assert config.get("default_model") == "qwen3-coder-30b"
models = {model["alias"]: model["model"] for model in config.get("models", [])}
assert models == {
    "qwen3-coder-30b": "qwen3-coder:30b",
    "gpt-oss-20b": "gpt-oss:20b",
}
PY
  if rg -n 'api\.atuin\.sh|openai\.com|openrouter|bedrock|warp' "$AI_SERVER_CONFIG"; then
    fail "Atuin AI server config contains a cloud or Warp endpoint"
  fi
  ok "Atuin AI server config is strict local AI"
fi

if [[ -f "$AI_SERVICE" ]]; then
  rg -q -- '-p 127\.0\.0\.1:8080:8080 ' "$AI_SERVICE" \
    || fail "atuin-ai service must publish only on loopback"
  rg -q '%h/\.config/atuin-ai/config\.toml:/etc/atuin-ai/config\.toml:ro,Z' "$AI_SERVICE" \
    || fail "atuin-ai service must mount config read-only with SELinux relabeling"
  rg -q 'ghcr.io/atuinsh/atuin-ai-server:latest$' "$AI_SERVICE" \
    || fail "atuin-ai service must run the Atuin AI server image"
  if rg -q -- '--network host' "$AI_SERVICE"; then
    fail "atuin-ai service must not use host networking"
  fi
  ok "Atuin AI service is loopback-only"
fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash atuin/tests/local-ai-config/run.sh
```

Expected: FAIL because `atuin/.config/atuin/config.toml` does not exist yet.

- [ ] **Step 3: Add Atuin to mise tools**

Modify `mise/.config/mise/config.toml` so `[tools]` contains `atuin = "latest"`:

```toml
[tools]
node = "24"
neovim = "0.12.2"
lazygit = "latest"
"npm:@openai/codex" = "latest"
go = "latest"
atuin = "latest"
```

- [ ] **Step 4: Add Atuin client config**

Create `atuin/.config/atuin/config.toml`:

```toml
auto_sync = false
update_check = false
sync_address = "http://127.0.0.1:9"

search_mode = "fuzzy"
filter_mode = "workspace"
filter_mode_shell_up_key_binding = "directory"
workspaces = true
style = "compact"
inline_height = 20
enter_accept = false
keymap_mode = "auto"
secrets_filter = true

[daemon]
enabled = true
autostart = true

[ai]
enabled = true
endpoint = "http://localhost:8080"
endpoint_protocol = "oss"
model = "qwen3-coder-30b"
yolo = false

[ai.capabilities]
enable_history_search = true
enable_history_output = false
enable_file_tools = false
enable_command_execution = false

[ai.opening]
send_cwd = true
send_last_command = false

[search]
authors = ["$all-user"]
```

- [ ] **Step 5: Wire Atuin into zsh after mise activation**

Modify `zsh/.zshrc` so the block after `eval "$(mise activate zsh)"` becomes:

```zsh
eval "$(starship init zsh)"
eval "$(mise activate zsh)"

if (( $+commands[atuin] )); then
  eval "$(atuin init zsh --disable-up-arrow)"
fi

# Per-machine env (gitignored on each machine, sourced if present)
[ -r ~/.openclaw/.env ] && set -a && . ~/.openclaw/.env && set +a
```

- [ ] **Step 6: Run the config test**

Run:

```bash
bash atuin/tests/local-ai-config/run.sh
```

Expected: PASS for Atuin client config, no cloud endpoint, mise installs Atuin, and zsh initializes Atuin conservatively. The AI server sections are skipped until Task 2 creates those files.

- [ ] **Step 7: Run zsh syntax check**

Run:

```bash
zsh -n zsh/.zshrc
```

Expected: exit code 0 with no output.

- [ ] **Step 8: Commit**

```bash
git add mise/.config/mise/config.toml zsh/.zshrc atuin/.config/atuin/config.toml atuin/tests/local-ai-config/run.sh
git commit -m "feat: add atuin local ai client config"
```

### Task 2: Add Local Atuin AI Backend Config And Service

**Files:**
- Create: `atuin/.config/atuin-ai/config.toml`
- Create: `atuin/.config/systemd/user/atuin-ai.service`
- Modify: `atuin/tests/local-ai-config/run.sh`

**Interfaces:**
- Consumes: Atuin client endpoint `http://localhost:8080` from Task 1.
- Produces: Atuin AI server config with aliases `qwen3-coder-30b` and `gpt-oss-20b`.
- Produces: user systemd service `atuin-ai.service` that runs the OSS Atuin AI backend through `/usr/sbin/podman`.

- [ ] **Step 1: Confirm the existing test fails on missing backend files**

Run:

```bash
test -f atuin/.config/atuin-ai/config.toml
```

Expected: FAIL with exit code 1 because the backend config has not been created yet.

- [ ] **Step 2: Add Atuin AI server config**

Create `atuin/.config/atuin-ai/config.toml`:

```toml
port = 8080
endpoint = "http://host.containers.internal:11434/v1"
api_key = "ollama"
default_model = "qwen3-coder-30b"

[request.body]
stream_options = { include_usage = true }

[[models]]
alias = "qwen3-coder-30b"
name = "Qwen3 Coder 30B"
description = "Local Ollama coding model for Atuin AI"
model = "qwen3-coder:30b"

[[models]]
alias = "gpt-oss-20b"
name = "GPT OSS 20B"
description = "Local Ollama fallback model for general reasoning"
model = "gpt-oss:20b"
```

- [ ] **Step 3: Add user systemd service**

Create `atuin/.config/systemd/user/atuin-ai.service`:

```ini
[Unit]
Description=Atuin AI local backend
Documentation=https://docs.atuin.sh/cli/ai/self-hosting/
After=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/bin/test -r %h/.config/atuin-ai/config.toml
ExecStart=/usr/sbin/podman run --rm --name atuin-ai-server -p 127.0.0.1:8080:8080 -v %h/.config/atuin-ai/config.toml:/etc/atuin-ai/config.toml:ro,Z ghcr.io/atuinsh/atuin-ai-server:latest
ExecStop=/usr/sbin/podman stop atuin-ai-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

- [ ] **Step 4: Run the config test**

Run:

```bash
bash atuin/tests/local-ai-config/run.sh
```

Expected: PASS including the backend config and systemd service checks.

- [ ] **Step 5: Verify systemd unit syntax when systemd is available**

Run:

```bash
systemd-analyze --user verify atuin/.config/systemd/user/atuin-ai.service
```

Expected: exit code 0. If this fails because the user manager is unavailable in the execution environment, record the exact error and continue after the static config test passes.

- [ ] **Step 6: Commit**

```bash
git add atuin/.config/atuin-ai/config.toml atuin/.config/systemd/user/atuin-ai.service atuin/tests/local-ai-config/run.sh
git commit -m "feat: add atuin local ai backend service"
```

### Task 3: Add Operator Notes And End-To-End Verification

**Files:**
- Create: `docs/solutions/tooling-decisions/atuin-local-ai.md`

**Interfaces:**
- Consumes: Atuin client config from Task 1 and backend service from Task 2.
- Produces: exact local setup and verification commands for installing runtime dependencies, pulling models, starting services, and confirming no cloud fallback.

- [ ] **Step 1: Write operator documentation**

Create `docs/solutions/tooling-decisions/atuin-local-ai.md`:

```markdown
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

Enable the Atuin AI backend service after stowing this repo:

```bash
systemctl --user daemon-reload
systemctl --user enable --now atuin-ai.service
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
endpoint = "http://host.containers.internal:11434/v1"
default_model = "qwen3-coder-30b"
```

Do not run `atuin login`, do not enable Atuin Hub sync, and do not replace the endpoint with OpenAI, OpenRouter, Bedrock, or Warp.

## Troubleshooting

If `?` in Atuin AI fails, check the local backend first:

```bash
systemctl --user status atuin-ai.service
curl --fail --silent --show-error http://localhost:11434/v1/models
curl --fail --silent --show-error http://localhost:8080/api/cli/models
```

If command generation is slow, switch `[ai] model` in `~/.config/atuin/config.toml` from `qwen3-coder-30b` to `gpt-oss-20b`.

If zsh starts but Atuin history is not recording commands, run:

```bash
atuin doctor
```

Confirm `atuin init zsh --disable-up-arrow` is loaded from `.zshrc` and that the shell is interactive.
```

- [ ] **Step 2: Run repository verification**

Run:

```bash
bash atuin/tests/local-ai-config/run.sh
zsh -n zsh/.zshrc
```

Expected: both commands exit 0. `bash atuin/tests/local-ai-config/run.sh` prints all `ok` lines.

- [ ] **Step 3: Run optional live probes only when dependencies are installed**

Run:

```bash
if command -v atuin >/dev/null 2>&1; then atuin doctor; else echo "atuin not installed yet"; fi
if command -v ollama >/dev/null 2>&1; then curl --fail --silent --show-error http://localhost:11434/v1/models; else echo "ollama not installed yet"; fi
if command -v systemctl >/dev/null 2>&1; then systemctl --user status atuin-ai.service --no-pager; else echo "systemctl unavailable"; fi
```

Expected: Atuin and Ollama probes either show local service information or print the explicit "not installed yet" messages. The systemd status may fail before the service is enabled; that is acceptable before manual installation.

- [ ] **Step 4: Commit**

```bash
git add docs/solutions/tooling-decisions/atuin-local-ai.md
git commit -m "docs: document atuin local ai setup"
```

### Task 4: Final Review

**Files:** none.

**Interfaces:**
- Consumes: all task commits.
- Produces: final verification result and any notes about uninstalled runtime dependencies.

- [ ] **Step 1: Inspect final diff against branch base**

Run:

```bash
git diff main...HEAD -- mise/.config/mise/config.toml zsh/.zshrc atuin docs/solutions/tooling-decisions/atuin-local-ai.md
```

Expected: only Atuin local AI config, tests, service, docs, and zsh/mise wiring are changed.

- [ ] **Step 2: Run final verification**

Run:

```bash
bash atuin/tests/local-ai-config/run.sh
zsh -n zsh/.zshrc
systemd-analyze --user verify atuin/.config/systemd/user/atuin-ai.service
```

Expected: config test passes, zsh syntax passes, and systemd unit verification passes or reports an environment-specific user-manager error that is documented in the handoff.

- [ ] **Step 3: Confirm working tree state**

Run:

```bash
git status --short --branch
```

Expected: clean working tree on the feature branch after all task commits.
