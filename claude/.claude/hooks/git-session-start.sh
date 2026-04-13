#!/usr/bin/env bash
# SessionStart hook: inject git/worktree context into Claude's session.
# Uses structured JSON output: additionalContext for Claude's reasoning,
# systemMessage for user-visible confirmation.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)
SESSION_ID=$(parse_session_id "$INPUT")

# --- CWD health check ---
if [[ ! -d "$PWD" ]]; then
  repo_hint=""
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    repo_hint="${BASH_REMATCH[1]}"
  fi
  msg="WARNING: Current directory no longer exists: $PWD."
  if [[ -n "$repo_hint" ]]; then
    ctx="CWD no longer exists: $PWD. The worktree was deleted. User must type at Claude Code prompt: ! cd \"$repo_hint\""
    msg+=" Worktree deleted -- run: ! cd \"$repo_hint\""
  else
    ctx="CWD no longer exists: $PWD. User must type at Claude Code prompt: ! cd <project-root>"
    msg+=" Run: ! cd <project-root>"
  fi
  emit_context_with_msg "SessionStart" "$ctx" "$msg"
  exit 0
fi

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
GIT_COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)

# State directory: one pending file per session needing a worktree.
STATE_DIR="$HOME/.claude/session-worktrees"
mkdir -p "$STATE_DIR"
# Clean up pending files older than 24 hours (abandoned sessions).
find "$STATE_DIR" -name 'pending-*' -mmin +1440 -delete 2>/dev/null || true

# Clean up stale cache and audit files — rate-limited to once per day.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
CLEANUP_MARKER="${CACHE_DIR}/.last-cleanup"
cleanup_needed=true
if [[ -f "$CLEANUP_MARKER" ]]; then
  cleanup_age=$(( EPOCHSECONDS - $(file_mtime "$CLEANUP_MARKER") ))
  (( cleanup_age < 86400 )) && cleanup_needed=false
fi
if [[ "$cleanup_needed" == "true" ]]; then
  if [[ -d "$CACHE_DIR" ]]; then
    find "$CACHE_DIR" \( \( -name 'notify-*' -mmin +1440 \) -o \
      \( \( -name 'statusline-git-*' -o -name 'commit-scopes-*' \) -mmin +10080 \) \
      \) -delete 2>/dev/null || true
  fi
  AUDIT_LOG_DIR="$HOME/.claude/logs"
  if [[ -d "$AUDIT_LOG_DIR" ]]; then
    find "$AUDIT_LOG_DIR" -name 'audit-*.log*' -mtime +90 -delete 2>/dev/null || true
  fi
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  touch "$CLEANUP_MARKER" 2>/dev/null || true
fi

# Detect if already in a linked worktree.
# Linked worktree: absolute-git-dir is under .git/worktrees/, differs from git-common-dir.
if [[ -n "$GIT_ABS_DIR" && -n "$GIT_COMMON_DIR" && "$GIT_ABS_DIR" != "$GIT_COMMON_DIR" ]]; then
  emit_context_with_msg "SessionStart" \
    "Worktree session active: branch=${BRANCH}, repo=${REPO}. Isolation confirmed. Commit each logical change atomically." \
    "[git-workflow] Worktree active (branch: ${BRANCH}). Isolation confirmed."
  exit 0
fi

# --- Main working tree path ---
# Accumulate context for Claude (CTX) and a short user message (MSG).
CTX=""
MSG=""

REMOTE_HEAD=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
MAIN_BRANCH="${REMOTE_HEAD#refs/remotes/origin/}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"

# If on a non-main branch, check whether it has been merged into remote main.
# Covers the GitHub-web-merge case: user merges on GitHub, starts a new session.
if [[ -n "$BRANCH" && "$BRANCH" != "$MAIN_BRANCH" && "$BRANCH" != "HEAD" ]]; then
  # Only fetch if FETCH_HEAD is older than 5 minutes (avoids redundant network
  # calls on rapid session restarts).
  fetch_head="${GIT_ABS_DIR}/FETCH_HEAD"
  fetch_age=999
  if [[ -f "$fetch_head" ]]; then
    fetch_age=$(( EPOCHSECONDS - $(file_mtime "$fetch_head") ))
  fi
  if (( fetch_age > 300 )); then
    git fetch origin "$MAIN_BRANCH" 2>/dev/null || true
  fi
  # Two detection strategies:
  # 1. Ancestry check: HEAD is reachable from origin/main (regular/fast-forward merge).
  # 2. Remote branch deleted: ls-remote exits 2 when the ref is absent (squash/rebase
  #    merge + GitHub auto-delete). Non-2 failures (network error) are not treated as merged.
  MERGED=false
  if git merge-base --is-ancestor HEAD "origin/$MAIN_BRANCH" 2>/dev/null; then
    MERGED=true
  else
    ls_rc=0
    timeout 5 git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1 || ls_rc=$?
    [[ $ls_rc -eq 2 ]] && MERGED=true
  fi
  if [[ "$MERGED" == "true" ]]; then
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
      CTX+="Warning: merged branch detected but worktree has uncommitted changes; skipping auto-checkout. "
    else
      git checkout "$MAIN_BRANCH" 2>/dev/null || true
      BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
      if [[ "$BRANCH" == "$MAIN_BRANCH" ]]; then
        git pull --ff-only origin "$MAIN_BRANCH" 2>/dev/null || \
          git pull origin "$MAIN_BRANCH" 2>/dev/null || true
        CTX+="Merged branch detected; switched to ${MAIN_BRANCH} and pulled latest. "
      fi
    fi
  fi
fi

# List existing linked worktrees so Claude knows where to resume open PR work.
# Prune stale entries — rate-limited to once per 30 minutes.
repo_key=${REPO//[^a-zA-Z0-9_]/_}
prune_marker="${CACHE_DIR}/.last-wt-prune-${repo_key}"
prune_needed=true
if [[ -f "$prune_marker" ]]; then
  prune_age=$(( EPOCHSECONDS - $(file_mtime "$prune_marker") ))
  (( prune_age < 1800 )) && prune_needed=false
fi
if [[ "$prune_needed" == "true" ]]; then
  git worktree prune 2>/dev/null || true
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  touch "$prune_marker" 2>/dev/null || true
fi
linked_wts=$(git worktree list 2>/dev/null | tail -n +2 || true)
if [[ -n "$linked_wts" ]]; then
  CTX+="Existing worktrees (may have open PRs): ${linked_wts}. To resume: start Claude Code from within a worktree directory. "
fi

# Main working tree: require EnterWorktree() before file edits.
if [[ -n "$SESSION_ID" ]]; then
  touch "$STATE_DIR/pending-${SESSION_ID}"
  CTX+="Main worktree (branch: ${BRANCH}). Call EnterWorktree() before any edits."
  MSG="[git-workflow] Main worktree (branch: ${BRANCH}). Call EnterWorktree() before any edits."
  if [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]; then
    CTX+=" MODE: no-pr -- merge to main and push directly after work. No PRs."
    MSG+=" MODE: no-pr"
  fi
else
  CTX+="Warning: no session ID; worktree isolation unavailable. Branch: ${BRANCH}"
  MSG="[git-workflow] Warning: no session ID; worktree isolation unavailable."
fi

emit_context_with_msg "SessionStart" "$CTX" "$MSG"
