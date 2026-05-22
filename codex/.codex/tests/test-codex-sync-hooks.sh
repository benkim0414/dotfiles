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

  if ! grep -Fq -- "$needle" "$file"; then
    printf 'expected %s to contain: %s\n' "$file" "$needle" >&2
    return 1
  fi
}

assert_top_level_contains() {
  local file="$1"
  local needle="$2"
  local first_table_line
  local end_line

  first_table_line="$(grep -n -- '^\[' "$file" | awk -F: '{ print $1; exit }' || true)"
  end_line="${first_table_line:-$(($(wc -l <"$file") + 1))}"

  if [[ "$end_line" -le 1 ]] || ! sed -n "1,$((end_line - 1))p" "$file" | grep -Fq -- "$needle"; then
    printf 'expected %s top-level config to contain: %s\n' "$file" "$needle" >&2
    return 1
  fi
}

assert_table_contains() {
  local file="$1"
  local table_header="$2"
  local needle="$3"
  local table_line
  local next_table_line
  local end_line

  table_line="$(grep -nF -- "$table_header" "$file" | awk -F: -v header="$table_header" '$0 == $1 ":" header { print $1; exit }' || true)"

  if [[ -z "$table_line" ]]; then
    printf 'expected %s to contain table: %s\n' "$file" "$table_header" >&2
    return 1
  fi

  next_table_line="$(awk -v start="$table_line" 'NR > start && /^\[/ { print NR; exit }' "$file")"
  end_line="${next_table_line:-$(($(wc -l <"$file") + 1))}"

  if [[ $((table_line + 1)) -ge "$end_line" ]]; then
    printf 'expected %s table %s to contain: %s\n' "$file" "$table_header" "$needle" >&2
    return 1
  fi

  if ! sed -n "$((table_line + 1)),$((end_line - 1))p" "$file" | grep -Fq -- "$needle"; then
    printf 'expected %s table %s to contain: %s\n' "$file" "$table_header" "$needle" >&2
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

copy_sync_fixture() {
  local dotfiles="$1"

  mkdir -p "$dotfiles/bin/.local/bin"
  mkdir -p "$dotfiles/codex/.codex/hooks"
  mkdir -p "$dotfiles/codex/.codex/tests"

  cp "$REPO_ROOT/bin/.local/bin/codex-sync" "$dotfiles/bin/.local/bin/codex-sync"
  cp "$REPO_ROOT/codex/.codex/config.base.toml" "$dotfiles/codex/.codex/config.base.toml"
  cp "$REPO_ROOT/codex/.codex/hooks/atomic-commits.sh" "$dotfiles/codex/.codex/hooks/atomic-commits.sh"
  cp "$REPO_ROOT/codex/.codex/hooks/worktree-guard.sh" "$dotfiles/codex/.codex/hooks/worktree-guard.sh"
}

TEST_ROOT="$(mktemp -d)"
DOTFILES="$TEST_ROOT/dotfiles"
HOME_DIR="$TEST_ROOT/home"
CODEX_HOME="$HOME_DIR/.codex"

copy_sync_fixture "$DOTFILES"
mkdir -p "$HOME_DIR"

printf '{"hooks":{"PreToolUse":[]}}\n' >"$DOTFILES/codex/.codex/hooks.json"
mkdir -p "$CODEX_HOME"
ln -s "$DOTFILES/codex/.codex/hooks.json" "$CODEX_HOME/hooks.json"

HOME="$HOME_DIR" DOTFILES="$DOTFILES" CODEX_HOME="$CODEX_HOME" "$DOTFILES/bin/.local/bin/codex-sync"

CONFIG="$DOTFILES/codex/.codex/config.toml"
EXPECTED_HOOK_PATH='PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.local/share/mise/installs/node/24/bin:/usr/local/bin:/usr/bin:/bin"'
assert_top_level_contains "$CONFIG" 'approval_policy = "on-request"'
assert_top_level_contains "$CONFIG" 'approvals_reviewer = "auto_review"'
assert_table_contains "$CONFIG" '[auto_review]' 'Approve routine sandbox-compatible repository work'
assert_table_contains "$CONFIG" '[mcp_servers.context-mode]' 'default_tools_approval_mode = "approve"'
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex pretooluse'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex posttooluse'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex sessionstart'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex precompact'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex userpromptsubmit'"
assert_file_contains "$CONFIG" "command = '$EXPECTED_HOOK_PATH context-mode hook codex stop'"
assert_file_contains "$CONFIG" 'command = '\''bash "$HOME/.codex/hooks/atomic-commits.sh"'\'''
assert_file_contains "$CONFIG" 'command = '\''bash "$HOME/.codex/hooks/worktree-guard.sh"'\'''
assert_file_contains "$CONFIG" "goals = true"

[[ "$(readlink "$CODEX_HOME/config.toml")" == "$DOTFILES/codex/.codex/config.toml" ]]
[[ "$(readlink "$CODEX_HOME/hooks/atomic-commits.sh")" == "$DOTFILES/codex/.codex/hooks/atomic-commits.sh" ]]
[[ "$(readlink "$CODEX_HOME/hooks/worktree-guard.sh")" == "$DOTFILES/codex/.codex/hooks/worktree-guard.sh" ]]
assert_path_absent "$CODEX_HOME/hooks.json"

printf '{"tool_input":{"command":"echo ok"}}' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/atomic-commits.sh"
jq -cn --arg cwd "$TEST_ROOT" --arg tool_name "Write" '{hook_event_name:"PreToolUse", tool_name:$tool_name, cwd:$cwd, tool_input:{file_path:"outside.txt", content:"ok"}}' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/worktree-guard.sh" >/dev/null

LIVE_PRIMARY_REPO="$TEST_ROOT/live-primary"
git init "$LIVE_PRIMARY_REPO" >/dev/null
git -C "$LIVE_PRIMARY_REPO" config user.email "codex@example.test"
git -C "$LIVE_PRIMARY_REPO" config user.name "Codex Test"
printf 'fixture\n' >"$LIVE_PRIMARY_REPO/README.md"
git -C "$LIVE_PRIMARY_REPO" add README.md
git -C "$LIVE_PRIMARY_REPO" commit -m "test: seed fixture" >/dev/null
live_guard_output="$(
  jq -cn --arg cwd "$LIVE_PRIMARY_REPO" --arg tool_name "mcp__context_mode__.ctx_execute" '{
    hook_event_name:"PreToolUse",
    tool_name:$tool_name,
    cwd:$cwd,
    tool_input:{language:"shell", code:"touch generated.txt"}
  }' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/worktree-guard.sh"
)"
jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$live_guard_output"
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("primary worktree")' >/dev/null <<<"$live_guard_output"

UNMANAGED_DOTFILES="$TEST_ROOT/unmanaged-dotfiles"
UNMANAGED_HOME="$TEST_ROOT/unmanaged-home"
UNMANAGED_CODEX_HOME="$UNMANAGED_HOME/.codex"
copy_sync_fixture "$UNMANAGED_DOTFILES"
mkdir -p "$UNMANAGED_CODEX_HOME/hooks"
ln -s /before/config "$UNMANAGED_CODEX_HOME/config.toml"
ln -s /before/atomic-commits.sh "$UNMANAGED_CODEX_HOME/hooks/atomic-commits.sh"
printf '{"hooks":{"PreToolUse":[]}}\n' >"$UNMANAGED_CODEX_HOME/hooks.json"

set +e
HOME="$UNMANAGED_HOME" DOTFILES="$UNMANAGED_DOTFILES" CODEX_HOME="$UNMANAGED_CODEX_HOME" "$UNMANAGED_DOTFILES/bin/.local/bin/codex-sync" >"$TEST_ROOT/unmanaged.out" 2>"$TEST_ROOT/unmanaged.err"
unmanaged_status=$?
set -e

if [[ "$unmanaged_status" -eq 0 ]]; then
  printf 'expected unmanaged hooks.json sync to fail\n' >&2
  exit 1
fi
assert_file_contains "$TEST_ROOT/unmanaged.err" "codex-sync: refusing to remove unmanaged hooks.json: $UNMANAGED_CODEX_HOME/hooks.json"
[[ "$(readlink "$UNMANAGED_CODEX_HOME/config.toml")" == "/before/config" ]]
[[ "$(readlink "$UNMANAGED_CODEX_HOME/hooks/atomic-commits.sh")" == "/before/atomic-commits.sh" ]]
assert_path_absent "$UNMANAGED_CODEX_HOME/hooks/worktree-guard.sh"

NONPRIMARY_DOTFILES="$TEST_ROOT/nonprimary-dotfiles"
NONPRIMARY_HOME="$TEST_ROOT/nonprimary-home"
copy_sync_fixture "$NONPRIMARY_DOTFILES"
mkdir -p "$NONPRIMARY_HOME"

HOME="$NONPRIMARY_HOME" DOTFILES="$NONPRIMARY_DOTFILES" "$NONPRIMARY_DOTFILES/bin/.local/bin/codex-sync" >"$TEST_ROOT/nonprimary.out" 2>"$TEST_ROOT/nonprimary.err"
assert_file_contains "$TEST_ROOT/nonprimary.err" "codex-sync: generated config only; set CODEX_HOME or CODEX_SYNC_LIVE=1 to wire live Codex paths from non-primary DOTFILES"
[[ -f "$NONPRIMARY_DOTFILES/codex/.codex/config.toml" ]]
assert_path_absent "$NONPRIMARY_HOME/.codex/config.toml"
assert_path_absent "$NONPRIMARY_HOME/.codex/hooks/atomic-commits.sh"
assert_path_absent "$NONPRIMARY_HOME/.codex/hooks/worktree-guard.sh"

INFERRED_DOTFILES="$TEST_ROOT/inferred-dotfiles"
INFERRED_HOME="$TEST_ROOT/inferred-home"
copy_sync_fixture "$INFERRED_DOTFILES"
mkdir -p "$INFERRED_HOME"

HOME="$INFERRED_HOME" "$INFERRED_DOTFILES/bin/.local/bin/codex-sync" >"$TEST_ROOT/inferred.out" 2>"$TEST_ROOT/inferred.err"
assert_file_contains "$TEST_ROOT/inferred.err" "codex-sync: generated config only; set CODEX_HOME or CODEX_SYNC_LIVE=1 to wire live Codex paths from non-primary DOTFILES"
[[ -f "$INFERRED_DOTFILES/codex/.codex/config.toml" ]]
assert_path_absent "$INFERRED_HOME/.codex/config.toml"
assert_path_absent "$INFERRED_HOME/.codex/hooks/atomic-commits.sh"
assert_path_absent "$INFERRED_HOME/.codex/hooks/worktree-guard.sh"

printf 'ok codex sync hook wiring\n'
