#!/usr/bin/env bash
# PostToolUse hook (matcher: ExitWorktree):
# Remind Claude of the required next steps after leaving the worktree.
# Uses structured JSON output for context injection.
# Never exit non-zero (PostToolUse should not block).
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

if [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]; then
  emit_context "PostToolUse" "Worktree exited. Merge the feature branch to main, then push."
else
  emit_context "PostToolUse" "Worktree exited. Wait for user to merge the PR, then run /pr:merge."
fi
