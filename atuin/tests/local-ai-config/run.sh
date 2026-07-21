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

def check(condition, message):
    if not condition:
        raise SystemExit(message)

path = sys.argv[1]
with open(path, "rb") as fh:
    config = tomllib.load(fh)

ai = config.get("ai", {})
capabilities = ai.get("capabilities", {})
opening = ai.get("opening", {})

check(config.get("auto_sync") is False, "auto_sync must be false")
check(config.get("update_check") is False, "update_check must be false")
check(config.get("sync_address") == "http://127.0.0.1:9", "sync_address must be disabled locally")
check(config.get("enter_accept") is False, "enter_accept must be false")
check(config.get("secrets_filter") is True, "secrets_filter must be true")
check(ai.get("enabled") is True, "Atuin AI must be enabled")
check(ai.get("endpoint") == "http://localhost:8080", "Atuin AI endpoint must be localhost")
check(ai.get("endpoint_protocol") == "oss", "Atuin AI protocol must be oss")
check(ai.get("model") == "qwen3-coder-30b", "Atuin AI model must be qwen3-coder-30b")
check("api_token" not in ai, "Atuin AI client token must be absent while service is loopback-only and unauthenticated")
check(ai.get("yolo") is False, "Atuin AI yolo must be false")
check(capabilities.get("enable_history_search") is True, "history search must be enabled")
check(capabilities.get("enable_history_output") is False, "history output must be disabled")
check(capabilities.get("enable_file_tools") is False, "file tools must be disabled")
check(capabilities.get("enable_command_execution") is False, "command execution must be disabled")
check(opening.get("send_cwd") is True, "send_cwd must be true")
check(opening.get("send_last_command") is False, "send_last_command must be false")
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

[[ -f "$AI_SERVER_CONFIG" ]] \
  || fail "Atuin AI server config must exist"

python3 - "$AI_SERVER_CONFIG" <<'PY'
import sys
import tomllib

def check(condition, message):
    if not condition:
        raise SystemExit(message)

path = sys.argv[1]
with open(path, "rb") as fh:
    config = tomllib.load(fh)

check(config.get("port") == 8080, "Atuin AI server port must be 8080")
check(config.get("endpoint") == "http://host.containers.internal:11434/v1", "Atuin AI server must target local host Ollama from the container")
check(config.get("api_key") == "ollama", "Atuin AI server api_key must be ollama")
check(config.get("default_model") == "qwen3-coder-30b", "default model must be qwen3-coder-30b")
check(config.get("request", {}).get("body", {}).get("stream_options") == {"include_usage": True}, "stream usage must be enabled")
models = {model["alias"]: model["model"] for model in config.get("models", [])}
check(models == {
    "qwen3-coder-30b": "qwen3-coder:30b",
    "gpt-oss-20b": "gpt-oss:20b",
}, "model aliases must match expected local Ollama models")
PY
if rg -n 'api\.atuin\.sh|openai\.com|openrouter|bedrock|warp' "$AI_SERVER_CONFIG"; then
  fail "Atuin AI server config contains a cloud or Warp endpoint"
fi
ok "Atuin AI server config is strict local AI"

[[ -f "$AI_SERVICE" ]] \
  || fail "Atuin AI systemd user service must exist"

rg -q '^ExecStartPre=/usr/bin/test -r %h/.config/atuin-ai/config.toml$' "$AI_SERVICE" \
  || fail "atuin-ai service must require a readable local config"
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
