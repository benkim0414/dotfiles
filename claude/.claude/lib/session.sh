#!/usr/bin/env bash
# session.sh — shared session utilities for Claude Code hooks: structured
#              context injection, session-id parsing, and worktree/workflow
#              detection. Source this file; do not execute it directly.

# shellcheck source=portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/portability.sh"

# --- Structured context injection ---
# Hooks can return JSON with hookSpecificOutput to inject context into Claude's
# reasoning (additionalContext) and/or show a message to the user (systemMessage).
# These helpers produce the correct envelope for each hook event type.

# Emit additionalContext only (silent -- Claude sees it, the user does not).
# PostCompact is not a valid hookEventName for hookSpecificOutput (Claude Code
# rejects it), so for that event we emit systemMessage instead, which is
# injected into the system prompt after compaction and re-orients Claude.
# Arguments: $1 hook event name, $2 context string
# Outputs:   the hook JSON envelope on stdout
emit_context() {
  local event="$1" ctx="$2"
  if [[ "$event" == "PostCompact" ]]; then
    jq -n --arg c "$ctx" '{systemMessage: $c}'
  else
    jq -n --arg e "$event" --arg c "$ctx" \
      '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
  fi
}

# Emit additionalContext plus a user-visible systemMessage.
# Arguments: $1 hook event name, $2 context string, $3 short user message
# Outputs:   the hook JSON envelope on stdout
emit_context_with_msg() {
  local event="$1" ctx="$2" msg="$3"
  jq -n --arg e "$event" --arg c "$ctx" --arg m "$msg" \
    '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}, systemMessage: $m}'
}

# --- Session ID ---

# Parse and validate session_id from a hook JSON payload.
# Arguments: $1 JSON string
# Outputs:   the UUID on stdout, or nothing if missing/not a valid UUID
parse_session_id() {
  local sid
  sid=$(printf '%s' "$1" | jq -r '.session_id // empty' 2>/dev/null || true)
  if [[ "$sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    printf '%s' "$sid"
  fi
}

# --- Worktree pending state ---

STATE_DIR="$HOME/.claude/session-worktrees"

# Print the pending-worktree marker path for a session.
# Globals:   STATE_DIR (read)
# Arguments: $1 session id
# Outputs:   the marker file path on stdout
pending_file() { printf '%s' "$STATE_DIR/pending-${1}"; }

# Decide whether the current session still owes a worktree before file edits.
# Self-healing: if the pending marker exists but we are already in a linked
# worktree, the stale marker is cleared and the function returns 0. If genuinely
# pending, prints a block message to stderr and exits 2. No marker / no session
# id -> returns 0 silently.
# Globals:   STATE_DIR (read, via pending_file)
# Arguments: $1 session id
# Outputs:   block message on stderr when blocking
# Returns:   0 = allow; exits 2 = block
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

# --- Worktree / CWD detection ---

# Print the parent repo path when PWD is (or was) under a .claude/worktrees/
# directory; print nothing otherwise. Used to build the "! cd <repo>" recovery
# hint when a worktree CWD has been deleted.
# Globals:   PWD (read)
# Outputs:   the parent repo path on stdout, or nothing
cwd_repo_hint() {
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# Classify the current directory's git worktree kind.
# Outputs (stdout):
#   linked  -- inside a linked (git worktree add) working tree
#   main    -- inside the primary working tree
#   none    -- not in a git repo, or a bare repo
worktree_kind() {
  git rev-parse --git-dir >/dev/null 2>&1 || {
    printf 'none'
    return
  }
  [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && {
    printf 'none'
    return
  }
  local abs common
  abs=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
  common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
  if [[ -n "$abs" && -n "$common" && "$abs" != "$common" ]]; then
    printf 'linked'
  else
    printf 'main'
  fi
}

# --- Workflow mode ---

# Test whether the session runs in no-pr workflow mode. Single source for the
# CLAUDE_GIT_WORKFLOW env-var name and its "no-pr" contract; a future rename or
# added mode changes only this function.
# Globals:   CLAUDE_GIT_WORKFLOW (read)
# Returns:   0 when no-pr mode, 1 otherwise
workflow_no_pr() {
  [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]
}
