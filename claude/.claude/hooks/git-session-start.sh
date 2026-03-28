#!/usr/bin/env bash
# SessionStart hook: inject git/worktree context into Claude's session.
# Stdout is added to Claude's context; stderr is shown to the user.
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
# Reject anything that isn't a UUID to prevent unexpected jq output in file paths.
[[ "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || SESSION_ID=""

# Silently exit if not inside a git repository.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Skip bare repositories (no working tree to isolate).
if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  exit 0
fi

REPO=$(git rev-parse --show-toplevel 2>/dev/null || true)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
GIT_ABS_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null || true)

# State directory: one pending file per session needing a worktree.
STATE_DIR="$HOME/.claude/session-worktrees"
mkdir -p "$STATE_DIR"
# Clean up pending files older than 24 hours (abandoned sessions).
find "$STATE_DIR" -name 'pending-*' -mmin +1440 -delete 2>/dev/null || true

# Detect if already in a linked worktree.
# Linked worktree: absolute-git-dir is under .git/worktrees/, differs from git-common-dir.
if [[ -n "$GIT_ABS_DIR" && -n "$GIT_COMMON_DIR" && "$GIT_ABS_DIR" != "$GIT_COMMON_DIR" ]]; then
  echo "[git-workflow] Worktree session active: branch=${BRANCH}, repo=${REPO}"
  echo "[git-workflow] Isolation confirmed. Commit each logical change atomically."
  exit 0
fi

# Main working tree: require EnterWorktree() before file edits.
if [[ -n "$SESSION_ID" ]]; then
  touch "$STATE_DIR/pending-${SESSION_ID}"
fi

echo "[git-workflow] WORKTREE REQUIRED: You are in the main working tree of ${REPO}."
echo "[git-workflow] Current branch: ${BRANCH}"
echo "[git-workflow] ACTION REQUIRED: Call EnterWorktree() immediately before any file edits."
echo "[git-workflow] This creates an isolated worktree+branch so parallel sessions cannot conflict."
echo "[git-workflow] After entering the worktree, proceed with the task normally."
