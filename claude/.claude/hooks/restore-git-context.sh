#!/usr/bin/env bash
# restore-git-context.sh — re-inject git/worktree context after compaction.
#
# Event:   PostCompact
# Matcher: n/a
# Exit:    0 always (emits context JSON; silent if not in a git repo)
#
# Compaction is lossy -- it can drop instructions that SessionStart or
# UserPromptSubmit hooks injected. This hook restores the critical bits
# (deleted-CWD recovery, worktree vs main orientation) so Claude stays
# oriented after compaction.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

# CWD health check -- mirror SessionStart's deleted-worktree recovery.
if [[ ! -d "$PWD" ]]; then
  repo_hint=$(cwd_repo_hint)
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

# Skip bare repositories (no working tree to isolate).
if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

CTX=""

# Detect linked worktree vs main working tree.
if [[ "$(worktree_kind)" == "linked" ]]; then
  CTX="Post-compaction context: worktree session active (branch: ${BRANCH}). Isolation confirmed; edits are safe."
  if workflow_no_pr; then
    CTX+=" MODE: no-pr -- before ExitWorktree, run requesting-code-review until clean, then ce-compound."
  fi
else
  CTX="Post-compaction context: main worktree (branch: ${BRANCH}). Call EnterWorktree() before any edits."
  if workflow_no_pr; then
    CTX+=" MODE: no-pr -- run requesting-code-review until clean, then ce-compound, then finishing-a-development-branch option 1. Reference: ~/.claude/docs/superpowers-workflow.md."
  fi
fi

emit_context "PostCompact" "$CTX"
