#!/usr/bin/env bash
# PostToolUse hook (matcher: EnterWorktree):
# Clear the pending state file once the worktree is successfully entered.
# Stdout is added to Claude's context. Never exit non-zero (PostToolUse should not block).
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
# Reject anything that isn't a UUID to prevent unexpected jq output in file paths.
[[ "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || SESSION_ID=""

if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

PENDING="$HOME/.claude/session-worktrees/pending-${SESSION_ID}"
rm -f "$PENDING"

echo "[git-workflow] Worktree entered. Isolation confirmed; proceed with the task."
