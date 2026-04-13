#!/usr/bin/env bash
# UserPromptSubmit hook: inject targeted context based on the user's prompt
# and clear stale attention markers.
#
# Fires on EVERY user message — fast path (no match) must be <10ms.
# Uses pure bash extraction and string matching; jq/gh only on pattern match.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)

# --- Clear attention marker (always, if in tmux) ---
# The user is present — clear the notification marker so tmux status resets.
if [[ -n "${TMUX_PANE:-}" ]]; then
  rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/claude/attention/${TMUX_PANE}" 2>/dev/null || true
fi

# --- Fast-path: extract prompt without spawning jq ---
# The UserPromptSubmit payload is compact JSON with "prompt":"...".
# Use bash regex to extract the value; handles unescaped text (typical case).
# Falls back to jq only if the regex fails (e.g., prompt contains escaped quotes).
PROMPT=""
if [[ "$INPUT" =~ \"prompt\":\"([^\"]*)\" ]]; then
  PROMPT="${BASH_REMATCH[1]}"
elif [[ "$INPUT" == *'"prompt"'* ]]; then
  PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null || true)
fi

[[ -z "$PROMPT" ]] && exit 0

# Convert to lowercase for case-insensitive matching (bash 4+).
prompt_lower="${PROMPT,,}"

context=""

# --- Pattern: PR references ---
# Match "PR #123", "pr 123", "pull/123" first; fall back to standalone "#123".
# Separate branches to avoid BASH_REMATCH ambiguity across two regexes.
pr_num=""
if [[ "$prompt_lower" =~ (pr|pull)[[:space:]/#]*([0-9]+) ]]; then
  pr_num="${BASH_REMATCH[2]}"
elif [[ "$prompt_lower" =~ (^|[[:space:]])#([0-9]+)([[:space:]]|$) ]]; then
  pr_num="${BASH_REMATCH[2]}"
fi

if [[ -n "$pr_num" ]]; then
  pr_info=$(gh pr view "$pr_num" --json number,title,state,headRefName,url 2>/dev/null || true)
  if [[ -n "$pr_info" ]]; then
    pr_summary=$(printf '%s' "$pr_info" | jq -r '"PR #\(.number): \(.title) [\(.state)] branch=\(.headRefName) \(.url)"' 2>/dev/null || true)
    if [[ -n "$pr_summary" ]]; then
      context+="${pr_summary}. "
    fi
  fi
fi

# --- Pattern: worktree queries ---
if [[ "$prompt_lower" == *worktree* ]] ||
   [[ "$prompt_lower" == *"enterworktree"* ]] ||
   [[ "$prompt_lower" == *"exitworktree"* ]]; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    wt_list=$(git worktree list 2>/dev/null || true)
    if [[ -n "$wt_list" ]]; then
      context+="Current worktrees: ${wt_list}. "
    fi
  fi
fi

# --- Emit structured context if any patterns matched ---
[[ -z "$context" ]] && exit 0

emit_context "UserPromptSubmit" "$context"
