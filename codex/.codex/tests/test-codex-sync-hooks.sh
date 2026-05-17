#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_ROOT=""

cleanup() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    rm -rf "$TEST_ROOT"
  fi
}

trap cleanup EXIT

assert_file_contains() {
  local file="$1"
  local needle="$2"

  if ! grep -Fq "$needle" "$file"; then
    printf 'expected %s to contain: %s\n' "$file" "$needle" >&2
    return 1
  fi
}

assert_path_absent() {
  local path="$1"

  if [[ -e "$path" || -L "$path" ]]; then
    printf 'expected path to be absent: %s\n' "$path" >&2
    ls -l "$path" >&2
    return 1
  fi
}

TEST_ROOT="$(mktemp -d)"
DOTFILES="$TEST_ROOT/dotfiles"
HOME_DIR="$TEST_ROOT/home"
CODEX_HOME="$HOME_DIR/.codex"

mkdir -p "$DOTFILES/bin/.local/bin"
mkdir -p "$DOTFILES/codex/.codex/hooks"
mkdir -p "$DOTFILES/codex/.codex/tests"
mkdir -p "$HOME_DIR"

cp "$REPO_ROOT/bin/.local/bin/codex-sync" "$DOTFILES/bin/.local/bin/codex-sync"
cp "$REPO_ROOT/codex/.codex/config.base.toml" "$DOTFILES/codex/.codex/config.base.toml"
cp "$REPO_ROOT/codex/.codex/hooks/atomic-commits.sh" "$DOTFILES/codex/.codex/hooks/atomic-commits.sh"

printf '{"hooks":{"PreToolUse":[]}}\n' >"$DOTFILES/codex/.codex/hooks.json"
mkdir -p "$CODEX_HOME"
ln -s "$DOTFILES/codex/.codex/hooks.json" "$CODEX_HOME/hooks.json"

HOME="$HOME_DIR" DOTFILES="$DOTFILES" CODEX_HOME="$CODEX_HOME" "$DOTFILES/bin/.local/bin/codex-sync"

CONFIG="$DOTFILES/codex/.codex/config.toml"
EXPECTED_HOOK_PATH='PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.local/share/mise/installs/node/24/bin:/usr/local/bin:/usr/bin:/bin"'
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex pretooluse'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex posttooluse'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex sessionstart'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex precompact'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex userpromptsubmit'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex stop'"
assert_file_contains "$CONFIG" 'command = '\''bash "$HOME/.codex/hooks/atomic-commits.sh"'\'''

[[ "$(readlink "$CODEX_HOME/config.toml")" == "$DOTFILES/codex/.codex/config.toml" ]]
[[ "$(readlink "$CODEX_HOME/hooks/atomic-commits.sh")" == "$DOTFILES/codex/.codex/hooks/atomic-commits.sh" ]]
assert_path_absent "$CODEX_HOME/hooks.json"

printf '{"tool_input":{"command":"echo ok"}}' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/atomic-commits.sh"
printf 'ok codex sync hook wiring\n'
