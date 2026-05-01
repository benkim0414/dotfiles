#!/usr/bin/env bash
# Codex UserPromptSubmit hook: inject PR/issue context and clear attention markers.
set -euo pipefail

input=$(cat)

if [[ -n "${TMUX_PANE:-}" ]]; then
  rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/codex/attention/${TMUX_PANE}" 2>/dev/null || true
fi

prompt=$(printf '%s' "$input" | jq -r '.prompt // .tool_input.prompt // ""' 2>/dev/null || true)
[[ -n "$prompt" ]] || exit 0
prompt_lower="${prompt,,}"

num=""
if [[ "$prompt_lower" =~ (pr|pull)[[:space:]/#]*([0-9]+) ]]; then
  num="${BASH_REMATCH[2]}"
elif [[ "$prompt_lower" =~ (^|[[:space:]])#([0-9]{2,})([[:space:]]|$) ]]; then
  num="${BASH_REMATCH[2]}"
fi
[[ -n "$num" ]] || exit 0

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/codex"
mkdir -p "$cache_dir" 2>/dev/null || true
repo_key=$(git rev-parse --show-toplevel 2>/dev/null | tr -cs 'a-zA-Z0-9_' '_' || echo unknown)
cache="${cache_dir}/pr-or-issue-${repo_key}-${num}"
now="${EPOCHSECONDS:-$(date +%s)}"
summary=""

if [[ -f "$cache" ]]; then
  mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
  if [[ "$mtime" =~ ^[0-9]+$ ]] && (( now - mtime < 120 )); then
    summary=$(cat "$cache" 2>/dev/null || true)
  fi
fi

if [[ -z "$summary" ]]; then
  pr_info=$(gh pr view "$num" --json number,title,state,headRefName,url 2>/dev/null || true)
  if [[ -n "$pr_info" ]]; then
    summary=$(printf '%s' "$pr_info" | jq -r '"PR #\(.number): \(.title) [\(.state)] branch=\(.headRefName) \(.url)"' 2>/dev/null || true)
  fi
fi

if [[ -z "$summary" ]]; then
  issue_info=$(gh issue view "$num" --json number,title,state,url 2>/dev/null || true)
  if [[ -n "$issue_info" ]]; then
    summary=$(printf '%s' "$issue_info" | jq -r '"Issue #\(.number): \(.title) [\(.state)] \(.url)"' 2>/dev/null || true)
  fi
fi

[[ -n "$summary" ]] || exit 0
printf '%s' "$summary" > "$cache" 2>/dev/null || true

jq -cn --arg ctx "$summary" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
