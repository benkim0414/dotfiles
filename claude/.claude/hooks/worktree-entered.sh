#!/usr/bin/env bash
# worktree-entered.sh — clear pending state once a worktree is entered.
#
# Event:   PostToolUse
# Matcher: EnterWorktree
# Exit:    0 always (PostToolUse must not block; emits context JSON)
#
# Removes the session's pending-<id> marker so worktree-guard.sh stops
# blocking edits, then confirms isolation to Claude.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)
SESSION_ID=$(parse_session_id "$INPUT")

if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

rm -f "$(pending_file "$SESSION_ID")"

emit_context "PostToolUse" "Worktree entered. Isolation confirmed; proceed with the task."
