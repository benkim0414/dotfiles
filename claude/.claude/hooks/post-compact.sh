#!/usr/bin/env bash
# PostCompact hook: re-inject git/worktree context after context compaction.
#
# Compaction is lossy -- it can drop instructions that SessionStart or
# UserPromptSubmit hooks injected. This hook restores the critical bits
# so Claude retains orientation after compaction.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

# CWD health check -- mirror SessionStart's deleted-worktree recovery.
if [[ ! -d "$PWD" ]]; then
  repo_hint=""
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    repo_hint="${BASH_REMATCH[1]}"
  fi
  ctx="Post-compaction context: CWD no longer exists: $PWD."
  if [[ -n "$repo_hint" ]]; then
    ctx+=" Worktree deleted. User must type at Claude Code prompt: ! cd \"$repo_hint\""
  else
    ctx+=" User must type at Claude Code prompt: ! cd <project-root>"
  fi
  emit_context "PostCompact" "$ctx"
  exit 0
fi

# Not in a git repo -- nothing to re-inject.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
GIT_ABS_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
GIT_COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)

CTX=""

# Detect linked worktree vs main working tree.
if [[ -n "$GIT_ABS_DIR" && -n "$GIT_COMMON_DIR" && "$GIT_ABS_DIR" != "$GIT_COMMON_DIR" ]]; then
  CTX="Post-compaction context: worktree session active (branch: ${BRANCH}). Isolation confirmed; edits are safe."
else
  CTX="Post-compaction context: main worktree (branch: ${BRANCH}). Call EnterWorktree() before any edits."
  if [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]; then
    CTX+=" MODE: no-pr."
  fi
fi

emit_context "PostCompact" "$CTX"
