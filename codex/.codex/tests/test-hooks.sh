#!/usr/bin/env bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
GIT_SAFETY_HOOK="$HOOK_ROOT/git-safety.sh"
WORKTREE_GUARD_HOOK="$HOOK_ROOT/worktree-guard.sh"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

repo="$TMPDIR_ROOT/repo"
git init -q -b main "$repo"
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name "Hook Test"
printf 'initial
' > "$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "chore(test): initial"
git -C "$repo" branch feature
linked="$TMPDIR_ROOT/linked-worktree"
git -C "$repo" worktree add -q -b feature-worktree "$linked"

run_hook() {
  local cwd="$1"
  local cmd="$2"
  jq -cn --arg cwd "$cwd" --arg cmd "$cmd" '{cwd: $cwd, tool_input: {command: $cmd}}' | CODEX_GIT_WORKFLOW=no-pr bash "$GIT_SAFETY_HOOK"
}

assert_denied() {
  local name="$1"
  local cwd="$2"
  local cmd="$3"
  local output
  output=$(run_hook "$cwd" "$cmd")
  if ! jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    printf 'not ok - %s
expected deny, got: %s
' "$name" "$output" >&2
    return 1
  fi
  printf 'ok - %s
' "$name"
}

assert_allowed() {
  local name="$1"
  local cwd="$2"
  local cmd="$3"
  local output
  output=$(run_hook "$cwd" "$cmd")
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    printf 'not ok - %s
expected allow, got: %s
' "$name" "$output" >&2
    return 1
  fi
  printf 'ok - %s
' "$name"
}

assert_denied "blanket staging" "$repo" "git add ."
assert_denied "blanket staging with git -C" "$TMPDIR_ROOT" "git -C '$repo' add ."
assert_denied "direct commit on main" "$repo" "git commit -m test"
assert_denied "rebase blocked" "$repo" "git rebase main"
assert_denied "compound git write blocked" "$repo" "git status && git commit -m test"
git -C "$repo" checkout -q feature
assert_denied "feature branch push to main" "$TMPDIR_ROOT" "git -C '$repo' push origin HEAD:main"
git -C "$repo" checkout -q main
assert_allowed "no-pr main push allowed from main" "$repo" "git push origin HEAD:main"
assert_denied "absolute sensitive path blocked" "$repo" "cat $HOME/.ssh/id_ed25519"
assert_allowed "execpolicy dry-run is ignored by git hook" "$repo" "codex execpolicy check --pretty --rules rules -- git add ."

run_worktree_guard() {
  local cwd="$1"
  local payload="$2"
  local field="${3:-patch}"
  jq -cn --arg cwd "$cwd" --arg payload "$payload" --arg field "$field" \
    '{cwd: $cwd, tool_input: {($field): $payload}}' | bash "$WORKTREE_GUARD_HOOK"
}

assert_guard_denied() {
  local name="$1"
  local cwd="$2"
  local payload="$3"
  local field="${4:-patch}"
  local output
  output=$(run_worktree_guard "$cwd" "$payload" "$field")
  if ! jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    printf 'not ok - %s
expected deny, got: %s
' "$name" "$output" >&2
    return 1
  fi
  printf 'ok - %s
' "$name"
}

assert_guard_allowed() {
  local name="$1"
  local cwd="$2"
  local payload="$3"
  local field="${4:-patch}"
  local output
  output=$(run_worktree_guard "$cwd" "$payload" "$field")
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    printf 'not ok - %s
expected allow, got: %s
' "$name" "$output" >&2
    return 1
  fi
  printf 'ok - %s
' "$name"
}

main_patch='*** Begin Patch
*** Update File: file.txt
@@
 x
*** End Patch'
linked_patch="*** Begin Patch
*** Update File: $linked/file.txt
@@
 x
*** End Patch"

assert_guard_denied "worktree guard blocks main cwd fallback" "$repo" "$main_patch"
assert_guard_allowed "worktree guard allows absolute linked worktree patch" "$repo" "$linked_patch" command
