#!/usr/bin/env bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
HOOK="$HOOK_ROOT/worktree-guard.sh"
TEST_ROOT=""
PRIMARY_REPO=""
LINKED_WORKTREE=""
SPACE_PRIMARY_REPO=""
SPACE_LINKED_WORKTREE=""
SPACE_LINKED_GIT_DIR=""
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
  SPACE_PRIMARY_REPO="$TEST_ROOT/space primary"
  SPACE_LINKED_WORKTREE="$TEST_ROOT/space linked"
  OUTSIDE_DIR="$TEST_ROOT/outside"

  mkdir -p "$OUTSIDE_DIR"
  git init "$PRIMARY_REPO" >/dev/null
  git -C "$PRIMARY_REPO" config user.email "codex@example.test"
  git -C "$PRIMARY_REPO" config user.name "Codex Test"
  printf 'fixture\n' >"$PRIMARY_REPO/README.md"
  git -C "$PRIMARY_REPO" add README.md
  git -C "$PRIMARY_REPO" commit -m "test: seed fixture" >/dev/null
  git -C "$PRIMARY_REPO" worktree add "$LINKED_WORKTREE" -b fixture-worktree >/dev/null

  git init "$SPACE_PRIMARY_REPO" >/dev/null
  git -C "$SPACE_PRIMARY_REPO" config user.email "codex@example.test"
  git -C "$SPACE_PRIMARY_REPO" config user.name "Codex Test"
  printf 'fixture\n' >"$SPACE_PRIMARY_REPO/README.md"
  git -C "$SPACE_PRIMARY_REPO" add README.md
  git -C "$SPACE_PRIMARY_REPO" commit -m "test: seed fixture" >/dev/null
  git -C "$SPACE_PRIMARY_REPO" worktree add "$SPACE_LINKED_WORKTREE" -b fixture-space-worktree >/dev/null
  SPACE_LINKED_GIT_DIR="$(git -C "$SPACE_LINKED_WORKTREE" rev-parse --absolute-git-dir)"
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

run_hook_json_with_tool_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local tool_name="$3"
  local tool_input="$4"

  jq -cn \
    --arg cwd "$cwd" \
    --arg tool_workdir "$tool_workdir" \
    --arg tool_name "$tool_name" \
    --argjson tool_input "$tool_input" '{
      hook_event_name: "PreToolUse",
      tool_name: $tool_name,
      cwd: $cwd,
      tool_input: ($tool_input + {workdir: $tool_workdir})
    }' | bash "$HOOK"
}

run_hook_json_with_home() {
  local home="$1"
  local cwd="$2"
  local tool_name="$3"
  local tool_input="$4"

  jq -cn --arg cwd "$cwd" --arg tool_name "$tool_name" --argjson tool_input "$tool_input" '{
    hook_event_name: "PreToolUse",
    tool_name: $tool_name,
    cwd: $cwd,
    tool_input: $tool_input
  }' | HOME="$home" bash "$HOOK"
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

assert_allowed_command_with_tool_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local command="$3"
  local output

  output="$(run_hook_json_with_tool_workdir "$cwd" "$tool_workdir" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')")"
  if [[ -n "$output" ]]; then
    jq -e . >/dev/null <<<"$output"
    if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
      echo "expected allowed but denied: $command with workdir=$tool_workdir and cwd=$cwd" >&2
      echo "$output" >&2
      return 1
    fi
  fi
  echo "ok allowed $command with workdir=$tool_workdir and cwd=$cwd"
}

assert_denied_json_with_home() {
  local home="$1"
  local cwd="$2"
  local tool_name="$3"
  local tool_input="$4"
  local output

  output="$(run_hook_json_with_home "$home" "$cwd" "$tool_name" "$tool_input")"
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"
  jq -e '.hookSpecificOutput.permissionDecisionReason | contains("main worktree")' >/dev/null <<<"$output"
  jq -e '.hookSpecificOutput.permissionDecisionReason | contains("git worktree add .worktrees/")' >/dev/null <<<"$output"
  echo "ok denied $tool_name in $cwd with HOME=$home"
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

assert_denied_command_with_home() {
  local home="$1"
  local cwd="$2"
  local command="$3"
  assert_denied_json_with_home "$home" "$cwd" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')"
}

if [[ ! -x "$HOOK" ]]; then
  echo "missing executable hook: $HOOK" >&2
  exit 1
fi

setup_git_fixture

assert_allowed_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: note.txt\n+ok\n*** End Patch\n"}')"
assert_denied_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn --arg file_path "$PRIMARY_REPO/patch-generated.txt" '{cmd: "*** Begin Patch\n*** Add File: \($file_path)\n+blocked\n*** End Patch\n"}')"
assert_denied_json "$PRIMARY_REPO" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: repo.txt\n+blocked\n*** End Patch\n"}')"
assert_denied_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/generated.txt" '{file_path: $file_path, content: "blocked"}')"
assert_denied_json "$OUTSIDE_DIR" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/generated-from-outside.txt" '{file_path: $file_path, content: "blocked"}')"
assert_denied_json "$OUTSIDE_DIR" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/newdir/generated.txt" '{file_path: $file_path, content: "blocked"}')"
assert_allowed_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$OUTSIDE_DIR/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_allowed_json "$OUTSIDE_DIR" "Write" "$(jq -cn --arg file_path "$OUTSIDE_DIR/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_denied_json "$PRIMARY_REPO" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "touch generated.txt"}')"
assert_denied_json "$OUTSIDE_DIR" "mcp__context_mode__.ctx_execute" "$(jq -cn --arg code "touch \"$PRIMARY_REPO/mcp-quoted-generated.txt\"" '{language: "shell", code: $code}')"
assert_denied_json_with_home "$TEST_ROOT" "$OUTSIDE_DIR" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "touch \"$HOME/primary/mcp-env-generated.txt\""}')"
assert_denied_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "touch ../primary/mcp-relative-generated.txt"}')"
assert_denied_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "p=../primary; touch \"$p/mcp-indirect-generated.txt\""}')"
assert_denied_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "cd ../primary; touch mcp-cd-generated.txt"}')"
assert_denied_json "$OUTSIDE_DIR" "mcp__context_mode__.ctx_batch_execute" "$(jq -cn --arg command "touch \"$PRIMARY_REPO/mcp-batch-generated.txt\"" '{commands: [{label: "write", command: $command}], queries: ["write"]}')"
assert_denied_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_batch_execute" "$(jq -cn '{commands: [{label: "write", command: "touch ../primary/mcp-batch-relative-generated.txt"}], queries: ["write"]}')"
assert_allowed_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_batch_execute" "$(jq -cn '{commands: [{label: "status", command: "git -C ../primary status --short"}], queries: ["status"]}')"
assert_allowed_json "$PRIMARY_REPO" "mcp__context_mode__.ctx_batch_execute" "$(jq -cn '{commands: [{label: "status", command: "git status --short"}], queries: ["status"]}')"
assert_denied_command "$OUTSIDE_DIR" "printf 'blocked\n' >\"$PRIMARY_REPO/redirect-quoted-generated.txt\""
assert_denied_command "$OUTSIDE_DIR" "printf 'blocked\n' >>$PRIMARY_REPO/redirect-append-generated.txt"
assert_denied_command_with_home "$TEST_ROOT" "$OUTSIDE_DIR" 'touch "$HOME/primary/env-generated.txt"'
assert_allowed_json "$LINKED_WORKTREE" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: repo.txt\n+allowed\n*** End Patch\n"}')"
assert_allowed_json "$LINKED_WORKTREE" "Write" "$(jq -cn --arg file_path "$LINKED_WORKTREE/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_allowed_command_with_tool_workdir "$PRIMARY_REPO" "$LINKED_WORKTREE" "git add README.md"
assert_allowed_command "$PRIMARY_REPO" "git -C $LINKED_WORKTREE add README.md"
assert_denied_command "$LINKED_WORKTREE" "git -C $PRIMARY_REPO add README.md"
assert_denied_command "$OUTSIDE_DIR" "git -C \"$SPACE_PRIMARY_REPO\" add README.md"
assert_allowed_command "$OUTSIDE_DIR" "git -C \"$SPACE_LINKED_WORKTREE\" add README.md"
assert_allowed_command "$PRIMARY_REPO" "touch /tmp/worktree-guard-scratch-$$"

assert_allowed_command "$PRIMARY_REPO" "git status --short"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO status --short"
assert_allowed_command "$PRIMARY_REPO" "git diff -- README.md"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO diff -- README.md"
assert_allowed_command "$PRIMARY_REPO" "git ls-files"
assert_allowed_command "$PRIMARY_REPO" "git branch --show-current"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO branch --show-current"
assert_allowed_command "$PRIMARY_REPO" "git worktree add .worktrees/recovery -b recovery-branch"
assert_allowed_command "$PRIMARY_REPO" "rg -n fixture README.md"
assert_allowed_command "$OUTSIDE_DIR" "git -C ../primary status --short"
assert_allowed_command "$LINKED_WORKTREE" "git -C ../primary status --short"
assert_allowed_command "$PRIMARY_REPO" "sed -n '1,20p' README.md"
assert_allowed_command "$PRIMARY_REPO" "head README.md"
assert_allowed_command "$PRIMARY_REPO" "tail README.md"
assert_allowed_command "$PRIMARY_REPO" "wc -l README.md"
assert_allowed_command "$PRIMARY_REPO" "stat README.md"
assert_allowed_command "$PRIMARY_REPO" "ls"
assert_allowed_command "$PRIMARY_REPO" "pwd"
assert_denied_command "$PRIMARY_REPO" "git show HEAD:README.md > README.md"
assert_denied_command "$PRIMARY_REPO" "git diff --output=generated.diff"
assert_denied_command "$PRIMARY_REPO" "git show --output=generated.txt HEAD:README.md"
assert_denied_command "$PRIMARY_REPO" "git branch feature"
assert_denied_command "$PRIMARY_REPO" "git branch -D feature"
assert_denied_command "$PRIMARY_REPO" "git branch --delete feature"
assert_denied_command "$PRIMARY_REPO" "git branch -f feature HEAD"
assert_denied_command "$PRIMARY_REPO" "git branch --force feature HEAD"
assert_denied_command "$PRIMARY_REPO" "rg --pre touch fixture README.md"
assert_denied_command "$PRIMARY_REPO" "rg --pre=touch fixture README.md"
assert_denied_command "$PRIMARY_REPO" "sed -n -i '1p' README.md"
assert_denied_command "$PRIMARY_REPO" "sed -n --in-place=.bak '1p' README.md"
assert_denied_command "$PRIMARY_REPO" "find . -name README.md -delete"
assert_denied_command "$PRIMARY_REPO" "find . -name README.md -fprint generated.txt"
assert_denied_command "$PRIMARY_REPO" "find . -name README.md -fprintf generated.txt %p"
assert_denied_command "$OUTSIDE_DIR" "printf 'blocked\n' > $PRIMARY_REPO/abs-generated.txt"
assert_denied_command "$OUTSIDE_DIR" "touch \"$PRIMARY_REPO/quoted-generated.txt\""
assert_denied_command "$OUTSIDE_DIR" "git -C $PRIMARY_REPO add README.md"
assert_denied_command "$OUTSIDE_DIR" "touch ../primary/relative-generated.txt"
assert_denied_command "$OUTSIDE_DIR" "git -C ../primary branch feature"
assert_denied_command "$OUTSIDE_DIR" "sed -n -i '1p' ../primary/README.md"
assert_denied_command "$OUTSIDE_DIR" "printf 'blocked\n' > ../primary/relative-redirect.txt"
assert_denied_command "$OUTSIDE_DIR" "rg --pre touch fixture ../primary/README.md"
assert_denied_command "$LINKED_WORKTREE" "touch ../primary/linked-relative-generated.txt"
assert_denied_command "$LINKED_WORKTREE" "git -C ../primary branch feature"
assert_denied_command "$LINKED_WORKTREE" "sed -n -i '1p' ../primary/README.md"
assert_denied_command "$LINKED_WORKTREE" "printf 'blocked\n' > ../primary/linked-relative-redirect.txt"
assert_denied_command "$LINKED_WORKTREE" "rg --pre touch fixture ../primary/README.md"
assert_denied_command "$LINKED_WORKTREE" "p=../primary; touch \"\$p/linked-indirect-generated.txt\""
assert_denied_command "$LINKED_WORKTREE" "cd ../primary; touch linked-cd-generated.txt"
assert_denied_command "$LINKED_WORKTREE" "cd ../primary/; touch linked-cd-slash-generated.txt"
assert_denied_command "$LINKED_WORKTREE" "pushd ../primary; touch linked-pushd-generated.txt"
assert_denied_command "$SPACE_LINKED_WORKTREE" "git --git-dir \"$SPACE_PRIMARY_REPO/.git\" --work-tree \"$SPACE_PRIMARY_REPO\" add README.md"
assert_denied_command "$SPACE_LINKED_WORKTREE" "git --git-dir=\"$SPACE_PRIMARY_REPO/.git\" --work-tree=\"$SPACE_PRIMARY_REPO\" add README.md"
assert_denied_command "$SPACE_LINKED_WORKTREE" "git --git-dir \"$SPACE_PRIMARY_REPO/.git\" --work-tree \"$SPACE_LINKED_WORKTREE\" add README.md"
assert_denied_command "$SPACE_LINKED_WORKTREE" "git --git-dir=\"$SPACE_PRIMARY_REPO/.git\" --work-tree=\"$SPACE_LINKED_WORKTREE\" add README.md"
assert_denied_command "$SPACE_LINKED_WORKTREE" "git --git-dir=\"$SPACE_PRIMARY_REPO/.git\" add README.md"
assert_allowed_command "$SPACE_LINKED_WORKTREE" "git --git-dir \"$SPACE_LINKED_GIT_DIR\" --work-tree \"$SPACE_LINKED_WORKTREE\" add README.md"
assert_allowed_command "$SPACE_LINKED_WORKTREE" "git --git-dir=\"$SPACE_LINKED_GIT_DIR\" --work-tree=\"$SPACE_LINKED_WORKTREE\" add README.md"
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
