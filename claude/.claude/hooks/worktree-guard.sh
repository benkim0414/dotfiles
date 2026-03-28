#!/usr/bin/env bash
# PreToolUse hook (matchers: Bash, Write, Edit, MultiEdit):
# Block file-touching tools until EnterWorktree() has been called this session.
# Exit 0 = allow. Exit 2 = block (stderr shown to Claude as error).
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

PENDING="$HOME/.claude/session-worktrees/pending-${SESSION_ID}"

if [[ ! -f "$PENDING" ]]; then
  exit 0
fi

# Self-healing: if already in a linked worktree (PostToolUse may not have fired
# for built-in tools), clear the stale file and pass through.
# The pending file was only written inside a git repo, so --absolute-git-dir is safe.
GIT_ABS=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
GIT_COM=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [[ -n "$GIT_ABS" && -n "$GIT_COM" && "$GIT_ABS" != "$GIT_COM" ]]; then
  rm -f "$PENDING"
  exit 0
fi

echo "BLOCKED: This session requires an isolated git worktree before file edits." >&2
echo "" >&2
echo "Call EnterWorktree() now — it creates an isolated branch off HEAD automatically." >&2
echo "Write/Edit/Bash are blocked until the worktree is entered." >&2
echo "" >&2
echo "  Emergency escape: rm \"${PENDING}\"" >&2
exit 2
