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
assert config.get("endpoint") == "http://localhost:11434/v1"
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
  rg -q '^ExecStart=/usr/sbin/podman run --rm --name atuin-ai-server --network host ' "$AI_SERVICE" \
    || fail "atuin-ai service must run with Podman host networking"
  rg -q 'ghcr.io/atuinsh/atuin-ai-server:latest$' "$AI_SERVICE" \
    || fail "atuin-ai service must run the Atuin AI server image"
  ok "Atuin AI service uses local host networking"
fi
