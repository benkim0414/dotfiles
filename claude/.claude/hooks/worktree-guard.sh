#!/usr/bin/env bash
# PreToolUse hook (matchers: Write, Edit, MultiEdit, NotebookEdit):
# Block file-editing tools until EnterWorktree() has been called this session.
# Only applies to paths inside the git working tree; writes to external paths
# (e.g. ~/.claude/plans/, /tmp/) are always allowed.
# Exit 0 = allow. Exit 2 = block (stderr shown to Claude as error).
set -euo pipefail

# Fast exit: no sessions need worktrees → nothing to block.
STATE_DIR="$HOME/.claude/session-worktrees"
if [[ ! -d "$STATE_DIR" ]] || ! ls "$STATE_DIR"/pending-* >/dev/null 2>&1; then
  exit 0
fi

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)
SESSION_ID=$(parse_session_id "$INPUT")

if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

PF=$(pending_file "$SESSION_ID")

if [[ ! -f "$PF" ]]; then
  exit 0
fi

# Allow writes to paths outside the git working tree (plan files, temp files, etc.).
# Resolve symlinks so that stow-managed files (e.g. ~/.claude/settings.json →
# ~/workspace/dotfiles/claude/.claude/settings.json) are treated as repo files.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // empty' 2>/dev/null || true)
if [[ -n "$FILE_PATH" ]]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$REPO_ROOT" ]]; then
    resolved=$(realpath -m "$FILE_PATH" 2>/dev/null || grealpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    if [[ "$resolved" != "${REPO_ROOT}"/* ]]; then
      exit 0  # Target is outside the repo working tree — allow unconditionally.
    fi
  fi
fi

# Delegate to shared check (includes self-healing and block message).
check_worktree_pending "$SESSION_ID"
