#!/usr/bin/env bash
# PostToolUse hook (matcher: ExitWorktree):
# Remind Claude of the required next steps after leaving the worktree.
# Stdout is added to Claude's context. Never exit non-zero (PostToolUse should not block).
set -euo pipefail

if [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]; then
  echo "[git-workflow] Worktree exited. Merge the feature branch to main, then push."
else
  echo "[git-workflow] Worktree exited. Wait for user to merge the PR, then run /merge-pr."
fi
