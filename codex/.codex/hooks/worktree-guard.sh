#!/usr/bin/env bash
# Codex PreToolUse hook for apply_patch: block tracked-file edits on main.
set -euo pipefail

cat >/dev/null || true

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

git_abs_dir=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
git_common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
remote_head=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
main_branch="${remote_head#refs/remotes/origin/}"
main_branch="${main_branch:-main}"

if [[ -n "$git_abs_dir" && -n "$git_common_dir" && "$git_abs_dir" != "$git_common_dir" ]]; then
  exit 0
fi

if [[ "$branch" == "$main_branch" ]]; then
  jq -cn --arg reason "BLOCKED: apply_patch edits are not allowed from the main worktree. Create and enter an isolated worktree branch first." '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
fi
