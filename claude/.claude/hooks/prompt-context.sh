#!/usr/bin/env bash
# UserPromptSubmit hook: inject targeted context based on the user's prompt
# and clear stale attention markers.
#
# Fires on EVERY user message — fast path (no match) must be <10ms.
# Uses pure bash extraction and string matching; jq/gh only on pattern match.
set -euo pipefail

# Inline EPOCHSECONDS fallback (avoids sourcing session.sh on every message).
: "${EPOCHSECONDS:=$(date +%s)}"

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
# Standalone "#N" requires 2+ digits to avoid false positives ("step #1", "item #2").
pr_num=""
if [[ "$prompt_lower" =~ (pr|pull)[[:space:]/#]*([0-9]+) ]]; then
  pr_num="${BASH_REMATCH[2]}"
elif [[ "$prompt_lower" =~ (^|[[:space:]])#([0-9]{2,})([[:space:]]|$) ]]; then
  pr_num="${BASH_REMATCH[2]}"
fi

if [[ -n "$pr_num" ]]; then
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
  pr_cache="${cache_dir}/.pr-cache-${pr_num}"
  pr_summary=""

  # Check cache (120s TTL).
  if [[ -f "$pr_cache" ]]; then
    cache_mtime=$(stat -c %Y "$pr_cache" 2>/dev/null || stat -f %m "$pr_cache" 2>/dev/null || echo 0)
    cache_age=$(( EPOCHSECONDS - cache_mtime ))
    if (( cache_age < 120 )); then
      pr_summary=$(cat "$pr_cache" 2>/dev/null || true)
    fi
  fi

  # Cache miss — fetch from GitHub with a 3-second timeout.
  if [[ -z "$pr_summary" ]]; then
    pr_info=$(timeout 3 gh pr view "$pr_num" --json number,title,state,headRefName,url 2>/dev/null || true)
    if [[ -n "$pr_info" ]]; then
      pr_summary=$(printf '%s' "$pr_info" | jq -r '"PR #\(.number): \(.title) [\(.state)] branch=\(.headRefName) \(.url)"' 2>/dev/null || true)
      if [[ -n "$pr_summary" ]]; then
        mkdir -p "$cache_dir" 2>/dev/null || true
        printf '%s' "$pr_summary" > "$pr_cache" 2>/dev/null || true
      fi
    fi
  fi

  if [[ -n "$pr_summary" ]]; then
    context+="${pr_summary}. "
  fi
fi

# --- Emit structured context if any patterns matched ---
[[ -z "$context" ]] && exit 0

# Source session.sh only when we actually need emit_context (lazy load).
# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

emit_context "UserPromptSubmit" "$context"
