#!/usr/bin/env bash
# Shared session utilities for Claude Code hooks.
# Source this file; do not execute it directly.

# shellcheck source=portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/portability.sh"

# --- Session ID ---

# Parse and validate session_id from a JSON string.
# Usage: SESSION_ID=$(parse_session_id "$json")
# Returns empty string if missing or not a valid UUID.
parse_session_id() {
  local sid
  sid=$(printf '%s' "$1" | jq -r '.session_id // empty' 2>/dev/null || true)
  if [[ "$sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    printf '%s' "$sid"
  fi
}

# --- Worktree pending state ---

STATE_DIR="$HOME/.claude/session-worktrees"

# Path to the pending-worktree marker for a given session.
pending_file() { printf '%s' "$STATE_DIR/pending-${1}"; }

# Check whether the current session still needs a worktree.
# If the pending file exists but we're already in a linked worktree (self-healing),
# clears the file and returns 0. If genuinely pending, prints a block message to
# stderr and exits 2. If no pending file or no session ID, returns 0 silently.
#
# Usage: check_worktree_pending "$SESSION_ID"
check_worktree_pending() {
  local sid="$1"
  [[ -n "$sid" ]] || return 0

  local pf
  pf=$(pending_file "$sid")
  [[ -f "$pf" ]] || return 0

  # Self-healing: if already in a linked worktree, clear the stale marker.
  local git_abs git_com
  git_abs=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
  git_com=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
  if [[ -n "$git_abs" && -n "$git_com" && "$git_abs" != "$git_com" ]]; then
    rm -f "$pf"
    return 0
  fi

  echo "BLOCKED: This session requires an isolated git worktree before file edits." >&2
  echo "" >&2
  echo "Call EnterWorktree() now — it creates an isolated branch off HEAD automatically." >&2
  echo "File-editing tools are blocked until the worktree is entered." >&2
  echo "" >&2
  echo "  Emergency escape: rm \"${pf}\"" >&2
  exit 2
}
