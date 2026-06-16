#!/usr/bin/env bash
# worktree-exited.sh — remind Claude of next steps after leaving a worktree.
#
# Event:   PostToolUse
# Matcher: ExitWorktree
# Exit:    0 always (PostToolUse must not block; emits context JSON)
#
# Branches on workflow_no_pr (lib/session.sh): no-pr mode reminds to finish
# review + ce-compound then merge; PR mode reminds to wait for the user merge.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

if workflow_no_pr; then
  emit_context "PostToolUse" "Worktree exited. Before merging: confirm requesting-code-review + ce-compound completed on the feature branch. If not, re-enter the worktree (EnterWorktree with the same name) and finish. When clean: merge to main, then push."
else
  emit_context "PostToolUse" "Worktree exited. PR-mode: wait for user to merge the PR."
fi
