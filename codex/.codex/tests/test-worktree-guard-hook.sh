#!/usr/bin/env bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
HOOK="$HOOK_ROOT/worktree-guard.sh"
TEST_ROOT=""
PRIMARY_REPO=""
LINKED_WORKTREE=""
OUTSIDE_DIR=""

cleanup() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    rm -rf "$TEST_ROOT"
  fi
}

trap cleanup EXIT

setup_git_fixture() {
  TEST_ROOT="$(mktemp -d)"
  PRIMARY_REPO="$TEST_ROOT/primary"
  LINKED_WORKTREE="$TEST_ROOT/linked"
  OUTSIDE_DIR="$TEST_ROOT/outside"

  mkdir -p "$OUTSIDE_DIR"
  git init "$PRIMARY_REPO" >/dev/null
  git -C "$PRIMARY_REPO" config user.email "codex@example.test"
  git -C "$PRIMARY_REPO" config user.name "Codex Test"
  printf 'fixture\n' >"$PRIMARY_REPO/README.md"
  git -C "$PRIMARY_REPO" add README.md
  git -C "$PRIMARY_REPO" commit -m "test: seed fixture" >/dev/null
  git -C "$PRIMARY_REPO" worktree add "$LINKED_WORKTREE" -b fixture-worktree >/dev/null
}

run_hook_json() {
  local cwd="$1"
  local tool_name="$2"
  local tool_input="$3"

  jq -cn --arg cwd "$cwd" --arg tool_name "$tool_name" --argjson tool_input "$tool_input" '{
    hook_event_name: "PreToolUse",
    tool_name: $tool_name,
    cwd: $cwd,
    tool_input: $tool_input
  }' | bash "$HOOK"
}

assert_denied_json() {
  local cwd="$1"
  local tool_name="$2"
  local tool_input="$3"
  local output

  output="$(run_hook_json "$cwd" "$tool_name" "$tool_input")"
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"
  jq -e '.hookSpecificOutput.permissionDecisionReason | contains("main worktree")' >/dev/null <<<"$output"
  jq -e '.hookSpecificOutput.permissionDecisionReason | contains("git worktree add .worktrees/")' >/dev/null <<<"$output"
  echo "ok denied $tool_name in $cwd"
}

assert_allowed_json() {
  local cwd="$1"
  local tool_name="$2"
  local tool_input="$3"
  local output

  output="$(run_hook_json "$cwd" "$tool_name" "$tool_input")"
  if [[ -n "$output" ]]; then
    jq -e . >/dev/null <<<"$output"
    if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
      echo "expected allowed but denied: $tool_name in $cwd" >&2
      echo "$output" >&2
      return 1
    fi
  fi
  echo "ok allowed $tool_name in $cwd"
}

assert_denied_command() {
  local cwd="$1"
  local command="$2"
  assert_denied_json "$cwd" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')"
}

assert_allowed_command() {
  local cwd="$1"
  local command="$2"
  assert_allowed_json "$cwd" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')"
}

if [[ ! -x "$HOOK" ]]; then
  echo "missing executable hook: $HOOK" >&2
  exit 1
fi

setup_git_fixture

assert_allowed_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: note.txt\n+ok\n*** End Patch\n"}')"
assert_denied_json "$PRIMARY_REPO" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: repo.txt\n+blocked\n*** End Patch\n"}')"
assert_denied_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/generated.txt" '{file_path: $file_path, content: "blocked"}')"
assert_allowed_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$OUTSIDE_DIR/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_allowed_json "$LINKED_WORKTREE" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: repo.txt\n+allowed\n*** End Patch\n"}')"
assert_allowed_json "$LINKED_WORKTREE" "Write" "$(jq -cn --arg file_path "$LINKED_WORKTREE/generated.txt" '{file_path: $file_path, content: "allowed"}')"

assert_allowed_command "$PRIMARY_REPO" "git status --short"
assert_allowed_command "$PRIMARY_REPO" "git diff -- README.md"
assert_allowed_command "$PRIMARY_REPO" "rg -n fixture README.md"
assert_allowed_command "$PRIMARY_REPO" "sed -n '1,20p' README.md"
assert_allowed_command "$PRIMARY_REPO" "ls"
assert_allowed_command "$PRIMARY_REPO" "pwd"
assert_denied_command "$PRIMARY_REPO" "printf 'blocked\n' > generated.txt"
assert_denied_command "$PRIMARY_REPO" "touch generated.txt"
assert_denied_command "$PRIMARY_REPO" "git add README.md"
assert_denied_command "$PRIMARY_REPO" "apply_patch <<'PATCH'
*** Begin Patch
*** Add File: generated.txt
+blocked
*** End Patch
PATCH"
assert_allowed_command "$LINKED_WORKTREE" "printf 'allowed\n' > generated.txt"

printf 'ok worktree guard hook\n'
