#!/usr/bin/env bash
# PostToolUse hook (matcher: EnterWorktree):
# Clear the pending state file once the worktree is successfully entered.
# Stdout is added to Claude's context. Never exit non-zero (PostToolUse should not block).
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)
SESSION_ID=$(parse_session_id "$INPUT")

if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

rm -f "$(pending_file "$SESSION_ID")"

echo "[git-workflow] Worktree entered. Isolation confirmed; proceed with the task."
