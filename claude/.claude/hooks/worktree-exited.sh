#!/usr/bin/env bash
# PostToolUse hook (matcher: ExitWorktree):
# Remind Claude of the required next steps after leaving the worktree.
# Uses structured JSON output for context injection.
# Never exit non-zero (PostToolUse should not block).
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

if workflow_no_pr; then
  emit_context "PostToolUse" "Worktree exited. Before merging: confirm requesting-code-review + ce-compound completed on the feature branch. If not, re-enter the worktree (EnterWorktree with the same name) and finish. When clean: merge to main, then push."
else
  emit_context "PostToolUse" "Worktree exited. PR-mode: wait for user to merge the PR."
fi
