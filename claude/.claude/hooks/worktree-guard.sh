#!/usr/bin/env bash
# PreToolUse hook (matchers: Write, Edit, MultiEdit, NotebookEdit):
# Block file-editing tools until EnterWorktree() has been called this session.
# Only applies to paths inside the git working tree; writes to external paths
# (e.g. ~/.claude/plans/, /tmp/) are always allowed.
# Exit 0 = allow. Exit 2 = block (stderr shown to Claude as error).
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
# Reject anything that isn't a UUID to prevent unexpected jq output in file paths.
[[ "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || SESSION_ID=""

if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

PENDING="$HOME/.claude/session-worktrees/pending-${SESSION_ID}"

if [[ ! -f "$PENDING" ]]; then
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

# Self-healing: if already in a linked worktree (PostToolUse may not have fired
# for built-in tools), clear the stale file and pass through.
# The pending file was only written inside a git repo, so --absolute-git-dir is safe.
GIT_ABS=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
GIT_COM=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
if [[ -n "$GIT_ABS" && -n "$GIT_COM" && "$GIT_ABS" != "$GIT_COM" ]]; then
  rm -f "$PENDING"
  exit 0
fi

echo "BLOCKED: This session requires an isolated git worktree before file edits." >&2
echo "" >&2
echo "Call EnterWorktree() now — it creates an isolated branch off HEAD automatically." >&2
echo "File-editing tools are blocked until the worktree is entered." >&2
echo "" >&2
echo "  Emergency escape: rm \"${PENDING}\"" >&2
exit 2
