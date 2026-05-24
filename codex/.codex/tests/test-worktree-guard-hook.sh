#!/usr/bin/env bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
HOOK="$HOOK_ROOT/worktree-guard.sh"
TEST_ROOT=""
PRIMARY_REPO=""
LINKED_WORKTREE=""
SECOND_LINKED_WORKTREE=""
NESTED_LINKED_WORKTREE=""
FAKE_WORKTREE_DIR=""
EXTERNAL_LINKED_WORKTREE=""
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
  SECOND_LINKED_WORKTREE="$TEST_ROOT/linked-second"
  NESTED_LINKED_WORKTREE="$PRIMARY_REPO/.worktrees/nested-linked"
  FAKE_WORKTREE_DIR="$PRIMARY_REPO/.worktrees/plain-dir"
  EXTERNAL_LINKED_WORKTREE="$TEST_ROOT/external-linked"
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
  git -C "$PRIMARY_REPO" worktree add "$SECOND_LINKED_WORKTREE" -b fixture-second-worktree >/dev/null
  mkdir -p "$PRIMARY_REPO/.worktrees" "$FAKE_WORKTREE_DIR"
  git -C "$PRIMARY_REPO" worktree add "$NESTED_LINKED_WORKTREE" -b worktree-nested-linked >/dev/null
  git -C "$PRIMARY_REPO" worktree add "$EXTERNAL_LINKED_WORKTREE" -b fixture-external-worktree >/dev/null

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
  local payload

  payload="$(jq -cn --arg cwd "$cwd" --arg tool_name "$tool_name" --argjson tool_input "$tool_input" '{
    hook_event_name: "PreToolUse",
    tool_name: $tool_name,
    cwd: $cwd,
    tool_input: $tool_input
  }')"
  bash "$HOOK" <<<"$payload"
}

run_hook_json_with_tool_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local tool_name="$3"
  local tool_input="$4"
  local payload

  payload="$(jq -cn \
    --arg cwd "$cwd" \
    --arg tool_workdir "$tool_workdir" \
    --arg tool_name "$tool_name" \
    --argjson tool_input "$tool_input" '{
      hook_event_name: "PreToolUse",
      tool_name: $tool_name,
      cwd: $cwd,
      tool_input: ($tool_input + {workdir: $tool_workdir})
    }')"
  bash "$HOOK" <<<"$payload"
}

run_hook_json_with_top_level_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local tool_name="$3"
  local tool_input="$4"
  local payload

  payload="$(jq -cn \
    --arg cwd "$cwd" \
    --arg tool_workdir "$tool_workdir" \
    --arg tool_name "$tool_name" \
    --argjson tool_input "$tool_input" '{
      hook_event_name: "PreToolUse",
      tool_name: $tool_name,
      cwd: $cwd,
      workdir: $tool_workdir,
      tool_input: $tool_input
    }')"
  bash "$HOOK" <<<"$payload"
}

run_hook_json_with_arguments_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local tool_name="$3"
  local tool_input="$4"
  local payload

  payload="$(jq -cn \
    --arg cwd "$cwd" \
    --arg tool_workdir "$tool_workdir" \
    --arg tool_name "$tool_name" \
    --argjson tool_input "$tool_input" '{
      hook_event_name: "PreToolUse",
      tool_name: $tool_name,
      cwd: $cwd,
      arguments: ($tool_input + {workdir: $tool_workdir})
    }')"
  bash "$HOOK" <<<"$payload"
}

run_hook_json_with_transcript_workdir() {
  local home="$1"
  local cwd="$2"
  local tool_workdir="$3"
  local tool_name="$4"
  local tool_input="$5"
  local payload
  local transcript_dir
  local transcript_path
  local tool_use_id="call_workdir_from_transcript"
  local arguments

  transcript_dir="$home/.codex/sessions/2026/05/22"
  transcript_path="$transcript_dir/rollout-test.jsonl"
  mkdir -p "$transcript_dir"
  arguments="$(jq -cn --argjson tool_input "$tool_input" --arg workdir "$tool_workdir" '$tool_input + {workdir: $workdir}')"
  jq -cn \
    --arg call_id "$tool_use_id" \
    --arg arguments "$arguments" '{
      type: "response_item",
      payload: {
        type: "function_call",
        name: "exec_command",
        arguments: $arguments,
        call_id: $call_id
      }
    }' >"$transcript_path"

  payload="$(jq -cn \
    --arg cwd "$cwd" \
    --arg tool_name "$tool_name" \
    --arg transcript_path "$transcript_path" \
    --arg tool_use_id "$tool_use_id" \
    --argjson tool_input "$tool_input" '{
      hook_event_name: "PreToolUse",
      tool_name: $tool_name,
      cwd: $cwd,
      transcript_path: $transcript_path,
      tool_use_id: $tool_use_id,
      tool_input: $tool_input
    }')"
  HOME="$home" bash "$HOOK" <<<"$payload"
}

run_hook_json_with_home() {
  local home="$1"
  local cwd="$2"
  local tool_name="$3"
  local tool_input="$4"
  local payload

  payload="$(jq -cn --arg cwd "$cwd" --arg tool_name "$tool_name" --argjson tool_input "$tool_input" '{
    hook_event_name: "PreToolUse",
    tool_name: $tool_name,
    cwd: $cwd,
    tool_input: $tool_input
  }')"
  HOME="$home" bash "$HOOK" <<<"$payload"
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

assert_approval_required_json() {
  local cwd="$1"
  local tool_name="$2"
  local tool_input="$3"
  local expected_reason="$4"
  local output

  output="$(run_hook_json "$cwd" "$tool_name" "$tool_input")"
  assert_approval_required_output "$output" "$expected_reason"
  echo "ok approval required $tool_name in $cwd"
}

assert_approval_required_json_with_home() {
  local home="$1"
  local cwd="$2"
  local tool_name="$3"
  local tool_input="$4"
  local expected_reason="$5"
  local output

  output="$(run_hook_json_with_home "$home" "$cwd" "$tool_name" "$tool_input")"
  assert_approval_required_output "$output" "$expected_reason"
  echo "ok approval required $tool_name in $cwd with HOME=$home"
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

assert_allowed_command_with_top_level_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local command="$3"
  local output

  output="$(run_hook_json_with_top_level_workdir "$cwd" "$tool_workdir" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')")"
  if [[ -n "$output" ]]; then
    jq -e . >/dev/null <<<"$output"
    if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
      echo "expected allowed but denied: $command with top-level workdir=$tool_workdir and cwd=$cwd" >&2
      echo "$output" >&2
      return 1
    fi
  fi
  echo "ok allowed $command with top-level workdir=$tool_workdir and cwd=$cwd"
}

assert_allowed_command_with_arguments_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local command="$3"
  local output

  output="$(run_hook_json_with_arguments_workdir "$cwd" "$tool_workdir" "functions.exec_command" "$(jq -cn --arg cmd "$command" '{cmd: $cmd}')")"
  if [[ -n "$output" ]]; then
    jq -e . >/dev/null <<<"$output"
    if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
      echo "expected allowed but denied: $command with arguments workdir=$tool_workdir and cwd=$cwd" >&2
      echo "$output" >&2
      return 1
    fi
  fi
  echo "ok allowed $command with arguments workdir=$tool_workdir and cwd=$cwd"
}

assert_allowed_command_with_transcript_workdir() {
  local home="$1"
  local cwd="$2"
  local tool_workdir="$3"
  local command="$4"
  local output

  output="$(run_hook_json_with_transcript_workdir "$home" "$cwd" "$tool_workdir" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')")"
  if [[ -n "$output" ]]; then
    jq -e . >/dev/null <<<"$output"
    if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
      echo "expected allowed but denied: $command with transcript workdir=$tool_workdir and cwd=$cwd" >&2
      echo "$output" >&2
      return 1
    fi
  fi
  echo "ok allowed $command with transcript workdir=$tool_workdir and cwd=$cwd"
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

assert_approval_required_output() {
  local output="$1"
  local expected_reason="$2"

  jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"
  jq -e --arg expected_reason "$expected_reason" '
    .hookSpecificOutput.permissionDecisionReason | contains("requires explicit approval") and contains($expected_reason)
  ' >/dev/null <<<"$output"
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

assert_approval_required_command() {
  local cwd="$1"
  local command="$2"
  local expected_reason="$3"
  local output

  output="$(run_hook_json "$cwd" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')")"
  assert_approval_required_output "$output" "$expected_reason"
  echo "ok approval required $command in $cwd"
}

assert_approval_required_command_with_home() {
  local home="$1"
  local cwd="$2"
  local command="$3"
  local expected_reason="$4"
  local output

  output="$(run_hook_json_with_home "$home" "$cwd" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')")"
  assert_approval_required_output "$output" "$expected_reason"
  echo "ok approval required $command in $cwd with HOME=$home"
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
assert_approval_required_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn --arg file_path "$PRIMARY_REPO/patch-generated.txt" '{cmd: "*** Begin Patch\n*** Add File: \($file_path)\n+blocked\n*** End Patch\n"}')" "primary worktree"
assert_approval_required_json "$PRIMARY_REPO" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: repo.txt\n+blocked\n*** End Patch\n"}')" "primary worktree"
assert_approval_required_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/generated.txt" '{file_path: $file_path, content: "blocked"}')" "primary worktree"
assert_approval_required_json "$OUTSIDE_DIR" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/generated-from-outside.txt" '{file_path: $file_path, content: "blocked"}')" "primary worktree"
assert_approval_required_json "$OUTSIDE_DIR" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/newdir/generated.txt" '{file_path: $file_path, content: "blocked"}')" "primary worktree"
assert_allowed_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$OUTSIDE_DIR/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_allowed_json "$OUTSIDE_DIR" "Write" "$(jq -cn --arg file_path "$OUTSIDE_DIR/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_approval_required_json "$PRIMARY_REPO" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "touch generated.txt"}')" "primary worktree"
assert_approval_required_json "$OUTSIDE_DIR" "mcp__context_mode__.ctx_execute" "$(jq -cn --arg code "touch \"$PRIMARY_REPO/mcp-quoted-generated.txt\"" '{language: "shell", code: $code}')" "primary worktree"
assert_approval_required_json_with_home "$TEST_ROOT" "$OUTSIDE_DIR" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "touch \"$HOME/primary/mcp-env-generated.txt\""}')" "primary worktree"
assert_approval_required_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "touch ../primary/mcp-relative-generated.txt"}')" "cross-boundary"
assert_denied_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "p=../primary; touch \"$p/mcp-indirect-generated.txt\""}')"
assert_approval_required_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "cd ../primary; touch mcp-cd-generated.txt"}')" "cross-boundary"
assert_approval_required_json "$OUTSIDE_DIR" "mcp__context_mode__.ctx_batch_execute" "$(jq -cn --arg command "touch \"$PRIMARY_REPO/mcp-batch-generated.txt\"" '{commands: [{label: "write", command: $command}], queries: ["write"]}')" "primary worktree"
assert_approval_required_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_batch_execute" "$(jq -cn '{commands: [{label: "write", command: "touch ../primary/mcp-batch-relative-generated.txt"}], queries: ["write"]}')" "cross-boundary"
assert_allowed_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_batch_execute" "$(jq -cn '{commands: [{label: "status", command: "git -C ../primary status --short"}], queries: ["status"]}')"
assert_allowed_json "$PRIMARY_REPO" "mcp__context_mode__.ctx_batch_execute" "$(jq -cn '{commands: [{label: "status", command: "git status --short"}], queries: ["status"]}')"
assert_approval_required_json "$PRIMARY_REPO" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "git pull --force"}')" "primary worktree"
assert_allowed_json "$PRIMARY_REPO" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "git pull --ff-only"}')"
assert_approval_required_command "$OUTSIDE_DIR" "printf 'blocked\n' >\"$PRIMARY_REPO/redirect-quoted-generated.txt\"" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "printf 'blocked\n' >>$PRIMARY_REPO/redirect-append-generated.txt" "primary worktree"
assert_approval_required_command_with_home "$TEST_ROOT" "$OUTSIDE_DIR" 'touch "$HOME/primary/env-generated.txt"' "primary worktree"
assert_allowed_json "$LINKED_WORKTREE" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: repo.txt\n+allowed\n*** End Patch\n"}')"
assert_allowed_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn --arg file_path "$NESTED_LINKED_WORKTREE/direct-absolute.txt" '{cmd: "*** Begin Patch\n*** Add File: \($file_path)\n+allowed\n*** End Patch\n"}')"
assert_allowed_json "$OUTSIDE_DIR" "functions.apply_patch" "$(jq -cn --arg file_path "$NESTED_LINKED_WORKTREE/direct-raw-string.txt" '"*** Begin Patch\n*** Add File: \($file_path)\n+allowed\n*** End Patch\n"')"
assert_allowed_json "$NESTED_LINKED_WORKTREE" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: direct-relative.txt\n+allowed\n*** End Patch\n"}')"
assert_approval_required_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn --arg file_path "$FAKE_WORKTREE_DIR/direct-fake.txt" '{cmd: "*** Begin Patch\n*** Add File: \($file_path)\n+blocked\n*** End Patch\n"}')" "unregistered worktree-like path"
assert_approval_required_json "$OUTSIDE_DIR" "functions.apply_patch" "$(jq -cn --arg file_path "$PRIMARY_REPO/direct-raw-primary.txt" '"*** Begin Patch\n*** Add File: \($file_path)\n+blocked\n*** End Patch\n"')" "primary worktree"
assert_approval_required_json "$OUTSIDE_DIR" "functions.apply_patch" "$(jq -cn --arg file_path "$PRIMARY_REPO/direct-decoy-primary.txt" '{cmd: "", patch: "*** Begin Patch\n*** Add File: \($file_path)\n+blocked\n*** End Patch\n"}')" "primary worktree"
assert_allowed_json "$LINKED_WORKTREE" "Write" "$(jq -cn --arg file_path "$LINKED_WORKTREE/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_allowed_json "$NESTED_LINKED_WORKTREE" "Write" "$(jq -cn --arg file_path "$NESTED_LINKED_WORKTREE/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_allowed_command "$OUTSIDE_DIR" "git -C \"$EXTERNAL_LINKED_WORKTREE\" add README.md"
assert_approval_required_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$FAKE_WORKTREE_DIR/generated.txt" '{file_path: $file_path, content: "blocked"}')" "unregistered worktree-like path"
assert_approval_required_json "$LINKED_WORKTREE" "Write" "$(jq -cn --arg file_path "$SECOND_LINKED_WORKTREE/generated.txt" '{file_path: $file_path, content: "blocked"}')" "cross-boundary"
assert_approval_required_command "$PRIMARY_REPO" "touch .worktrees/plain-dir/generated.txt" "unregistered worktree-like path"
assert_allowed_command_with_tool_workdir "$PRIMARY_REPO" "$LINKED_WORKTREE" "git add README.md"
assert_allowed_command "$LINKED_WORKTREE" "git add README.md"
assert_allowed_command "$LINKED_WORKTREE" "git commit -m 'test: linked worktree commit'"
assert_allowed_command "$LINKED_WORKTREE" "printf 'allowed\n' > generated.txt"
assert_allowed_command "$LINKED_WORKTREE" "mkdir -p tmp && printf 'allowed\n' > tmp/generated.txt"
assert_allowed_command "$LINKED_WORKTREE" "npm test"
assert_allowed_command "$LINKED_WORKTREE" "gh pr create --repo owner/repo --head feature --title 'Test PR' --body 'Test body'"
assert_allowed_command "$PRIMARY_REPO" "git -C $LINKED_WORKTREE add README.md"
assert_allowed_command "$PRIMARY_REPO" "git -C $LINKED_WORKTREE commit -m 'test: linked worktree commit'"
assert_allowed_command_with_tool_workdir "$PRIMARY_REPO" "$NESTED_LINKED_WORKTREE" "apply_patch <<'PATCH'
*** Begin Patch
*** Add File: shell-apply-patch.txt
+allowed
*** End Patch
PATCH"
assert_allowed_command_with_top_level_workdir "$PRIMARY_REPO" "$NESTED_LINKED_WORKTREE" "apply_patch <<'PATCH'
*** Begin Patch
*** Add File: shell-apply-patch-top-level.txt
+allowed
*** End Patch
PATCH"
assert_allowed_command_with_arguments_workdir "$PRIMARY_REPO" "$NESTED_LINKED_WORKTREE" "apply_patch <<'PATCH'
*** Begin Patch
*** Add File: shell-apply-patch-arguments.txt
+allowed
*** End Patch
PATCH"
assert_allowed_command_with_transcript_workdir "$TEST_ROOT/home" "$PRIMARY_REPO" "$NESTED_LINKED_WORKTREE" "apply_patch <<'PATCH'
*** Begin Patch
*** Add File: shell-apply-patch-transcript.txt
+allowed
*** End Patch
PATCH"
assert_allowed_command_with_tool_workdir "$PRIMARY_REPO" "$NESTED_LINKED_WORKTREE" "git apply <<'PATCH'
diff --git a/git-apply.txt b/git-apply.txt
new file mode 100644
index 0000000..30d8405
--- /dev/null
+++ b/git-apply.txt
@@ -0,0 +1 @@
+allowed
PATCH"
assert_approval_required_command "$NESTED_LINKED_WORKTREE" "git apply <<'PATCH'
diff --git a/../primary/git-apply-cross-boundary.txt b/../primary/git-apply-cross-boundary.txt
new file mode 100644
index 0000000..30d8405
--- /dev/null
+++ b/../primary/git-apply-cross-boundary.txt
@@ -0,0 +1 @@
+blocked
PATCH" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "git reset --hard HEAD~1" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "git clean -fd" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "git branch -D old-branch" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "git push --force origin HEAD" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "git rebase -i HEAD~3" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "rm generated.txt" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "command rm generated.txt" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "env rm generated.txt" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "bash -c 'rm generated.txt'" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "bash -lc 'rm generated.txt'" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "rm -r tmp" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "rm -rf tmp" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "touch file;rm -rf tmp" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "git status&&rm -rf tmp" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "printf x|rm generated.txt" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "printf x | rm generated.txt" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "git status|rm -rf tmp" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "git -C \"$SPACE_LINKED_WORKTREE\" reset --hard HEAD" "destructive"
assert_approval_required_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "git status&&rm -rf tmp"}')" "destructive"
assert_approval_required_json "$LINKED_WORKTREE" "mcp__context_mode__.ctx_execute" "$(jq -cn '{language: "shell", code: "printf x|rm generated.txt"}')" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "find . -name '*.tmp' -delete" "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "chmod -R 777 ." "destructive"
assert_approval_required_command "$LINKED_WORKTREE" "git -C $PRIMARY_REPO add README.md" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "touch ../linked-second/sibling-generated.txt" "cross-boundary"
assert_approval_required_command "$OUTSIDE_DIR" "git -C \"$SPACE_PRIMARY_REPO\" add README.md" "primary worktree"
assert_allowed_command "$OUTSIDE_DIR" "git -C \"$SPACE_LINKED_WORKTREE\" add README.md"
assert_allowed_command "$OUTSIDE_DIR" "printf 'allowed\n' > scratch.txt"
assert_allowed_command "$OUTSIDE_DIR" "touch scratch.txt"
assert_allowed_command "$PRIMARY_REPO" "printf 'allowed\n' > /tmp/worktree-guard-scratch-$$"
assert_allowed_command "$PRIMARY_REPO" "printf 'allowed\n' > /tmp/worktree-guard-scratch-$$ 2>&1"
assert_allowed_command "$PRIMARY_REPO" "printf 'allowed\n' > /tmp/worktree-guard-scratch-$$ >&2"
assert_allowed_command "$PRIMARY_REPO" "touch /tmp/worktree-guard-scratch-$$"
assert_approval_required_command "$PRIMARY_REPO" "printf 'blocked\n' > /tmp/worktree-guard-scratch-$$ > generated.txt" "primary worktree"

assert_allowed_command "$PRIMARY_REPO" "git status --short"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO status --short"
assert_allowed_command "$PRIMARY_REPO" "git diff -- README.md"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO diff -- README.md"
assert_allowed_command "$PRIMARY_REPO" "git ls-files"
assert_allowed_command "$PRIMARY_REPO" "git branch --show-current"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO branch --show-current"
assert_allowed_command "$PRIMARY_REPO" "git pull"
assert_allowed_command "$PRIMARY_REPO" "git pull --ff-only"
assert_allowed_command "$PRIMARY_REPO" "git pull --rebase"
assert_allowed_command "$PRIMARY_REPO" "git pull origin"
assert_allowed_command "$PRIMARY_REPO" "git pull origin main"
assert_allowed_command "$PRIMARY_REPO" "git pull --ff-only origin main"
assert_allowed_command "$PRIMARY_REPO" "git pull --rebase origin main"
assert_allowed_command "$OUTSIDE_DIR" "git -C $PRIMARY_REPO pull --ff-only"
assert_approval_required_command "$PRIMARY_REPO" "git pull origin feature" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull upstream main" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --all" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --tags" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --force" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull -f" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --prune" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --ff-only --rebase" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull origin main extra" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --ff-only; touch generated.txt" "primary worktree"
assert_allowed_command "$PRIMARY_REPO" "git worktree add .worktrees/recovery -b recovery-branch"
assert_approval_required_command "$PRIMARY_REPO" "git worktree add .worktrees/nested/recovery -b nested-recovery-branch" "unregistered worktree-like path"
assert_approval_required_command "$PRIMARY_REPO" "git worktree add .worktrees/forced --force forced-branch" "unregistered worktree-like path"
assert_allowed_command "$PRIMARY_REPO" "touch .worktrees/nested-linked/generated-from-primary.txt"
assert_allowed_command "$PRIMARY_REPO" "git worktree remove .worktrees/nested-linked"
assert_allowed_command "$PRIMARY_REPO" "git worktree prune"
assert_allowed_command "$PRIMARY_REPO" "git checkout main"
assert_allowed_command "$PRIMARY_REPO" "git switch main"
assert_allowed_command "$PRIMARY_REPO" "git merge worktree-nested-linked"
assert_allowed_command "$PRIMARY_REPO" "git branch -d worktree-nested-linked"
assert_approval_required_command "$PRIMARY_REPO" "git worktree remove --force .worktrees/nested-linked" "primary worktree"
git -C "$PRIMARY_REPO" branch integration
git -C "$PRIMARY_REPO" checkout integration >/dev/null
assert_approval_required_command "$PRIMARY_REPO" "git merge worktree-nested-linked" "primary worktree"
git -C "$PRIMARY_REPO" checkout main >/dev/null
git -C "$PRIMARY_REPO" worktree remove .worktrees/nested-linked
assert_allowed_command "$PRIMARY_REPO" "git branch -d worktree-nested-linked"
git -C "$PRIMARY_REPO" branch merged-cleanup-branch
assert_allowed_command "$PRIMARY_REPO" "git branch -d merged-cleanup-branch"
assert_approval_required_command "$PRIMARY_REPO" "git branch -d unrelated-worktree-cleanup" "primary worktree"
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
assert_approval_required_command "$PRIMARY_REPO" "git show HEAD:README.md > README.md" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git diff --output=generated.diff" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git show --output=generated.txt HEAD:README.md" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git branch feature" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git branch -D feature" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git branch --delete feature" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git branch -f feature HEAD" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git branch --force feature HEAD" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git branch -d main" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git branch -D worktree-nested-linked" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git reset --hard HEAD" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git rebase HEAD~1" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git push --force origin main" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "rg --pre touch fixture README.md" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "rg --pre=touch fixture README.md" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "sed -n -i '1p' README.md" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "sed -n --in-place=.bak '1p' README.md" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "find . -name README.md -delete" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "find . -name README.md -fprint generated.txt" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "find . -name README.md -fprintf generated.txt %p" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "printf 'blocked\n' > $PRIMARY_REPO/abs-generated.txt" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "touch \"$PRIMARY_REPO/quoted-generated.txt\"" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "git -C $PRIMARY_REPO add README.md" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "touch ../primary/relative-generated.txt" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "git -C ../primary branch feature" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "sed -n -i '1p' ../primary/README.md" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "printf 'blocked\n' > ../primary/relative-redirect.txt" "primary worktree"
assert_approval_required_command "$OUTSIDE_DIR" "rg --pre touch fixture ../primary/README.md" "primary worktree"
assert_approval_required_command "$LINKED_WORKTREE" "touch ../primary/linked-relative-generated.txt" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "printf 'blocked\n' > ../primary/linked-relative-redirect.txt" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "git -C ../primary add README.md" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "git -C ../primary branch feature" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "sed -n -i '1p' ../primary/README.md" "cross-boundary"
assert_approval_required_json "$LINKED_WORKTREE" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/generated.txt" '{file_path: $file_path, content: "blocked"}')" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "rg --pre touch fixture ../primary/README.md" "cross-boundary"
assert_denied_command "$LINKED_WORKTREE" "p=../primary; touch \"\$p/linked-indirect-generated.txt\""
assert_approval_required_command "$LINKED_WORKTREE" "cd ../primary; touch linked-cd-generated.txt" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "cd ../primary/; touch linked-cd-slash-generated.txt" "cross-boundary"
assert_approval_required_command "$LINKED_WORKTREE" "pushd ../primary; touch linked-pushd-generated.txt" "cross-boundary"
assert_approval_required_command "$SPACE_LINKED_WORKTREE" "git --git-dir \"$SPACE_PRIMARY_REPO/.git\" --work-tree \"$SPACE_PRIMARY_REPO\" add README.md" "cross-boundary"
assert_approval_required_command "$SPACE_LINKED_WORKTREE" "git --git-dir=\"$SPACE_PRIMARY_REPO/.git\" --work-tree=\"$SPACE_PRIMARY_REPO\" add README.md" "cross-boundary"
assert_approval_required_command "$SPACE_LINKED_WORKTREE" "git --git-dir \"$SPACE_PRIMARY_REPO/.git\" --work-tree \"$SPACE_LINKED_WORKTREE\" add README.md" "cross-boundary"
assert_approval_required_command "$SPACE_LINKED_WORKTREE" "git --git-dir=\"$SPACE_PRIMARY_REPO/.git\" --work-tree=\"$SPACE_LINKED_WORKTREE\" add README.md" "cross-boundary"
assert_approval_required_command "$SPACE_LINKED_WORKTREE" "git --git-dir=\"$SPACE_PRIMARY_REPO/.git\" add README.md" "cross-boundary"
assert_allowed_command "$SPACE_LINKED_WORKTREE" "git --git-dir \"$SPACE_LINKED_GIT_DIR\" add README.md"
assert_allowed_command "$OUTSIDE_DIR" "git -C \"$SPACE_LINKED_WORKTREE\" --git-dir \"$SPACE_LINKED_GIT_DIR\" add README.md"
assert_allowed_command "$SPACE_LINKED_WORKTREE" "git --git-dir \"$SPACE_LINKED_GIT_DIR\" --work-tree \"$SPACE_LINKED_WORKTREE\" add README.md"
assert_allowed_command "$SPACE_LINKED_WORKTREE" "git --git-dir=\"$SPACE_LINKED_GIT_DIR\" --work-tree=\"$SPACE_LINKED_WORKTREE\" add README.md"
assert_approval_required_command "$PRIMARY_REPO" "printf 'blocked\n' > generated.txt" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "touch generated.txt" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git add README.md" "primary worktree"
assert_approval_required_json "$PRIMARY_REPO" "Write" "$(jq -cn '{file_path: "generated.txt", content: "blocked"}')" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "apply_patch <<'PATCH'
*** Begin Patch
*** Add File: generated.txt
+blocked
*** End Patch
PATCH" "primary worktree"

printf 'ok worktree guard hook\n'
