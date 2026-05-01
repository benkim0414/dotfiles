#!/usr/bin/env bash
# Codex SessionStart hook: inject the repo's git workflow context.
set -euo pipefail

json_escape() {
  jq -Rn --arg s "$1" '$s'
}

emit_context() {
  local context="$1" message="${2:-}"
  local context_json message_json
  context_json=$(json_escape "$context")
  message_json=$(json_escape "$message")
  if [[ -n "$message" ]]; then
    printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
      "$message_json" "$context_json"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
      "$context_json"
  fi
}

# Drain stdin so Codex can pipe hook payloads without risking SIGPIPE.
cat >/dev/null || true

if [[ ! -d "$PWD" ]]; then
  emit_context "Current directory no longer exists: $PWD. Start a new shell in the project root before continuing." \
    "[git-workflow] Current directory no longer exists."
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  exit 0
fi

repo=$(git rev-parse --show-toplevel 2>/dev/null || true)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
git_abs_dir=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
git_common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
remote_head=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
main_branch="${remote_head#refs/remotes/origin/}"
main_branch="${main_branch:-main}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/codex"
mkdir -p "$cache_dir" 2>/dev/null || true
cleanup_marker="${cache_dir}/.last-workflow-cleanup"
now="${EPOCHSECONDS:-$(date +%s)}"
cleanup_needed=true
if [[ -d "$cache_dir" && -f "$cleanup_marker" ]]; then
  last=$(cat "$cleanup_marker" 2>/dev/null || echo 0)
  [[ "$last" =~ ^[0-9]+$ ]] && (( now - last < 86400 )) && cleanup_needed=false
fi
if [[ "$cleanup_needed" == "true" && -d "$cache_dir" ]]; then
  find "$cache_dir" -name 'notify-*' -mmin +1440 -delete 2>/dev/null || true
  find "$cache_dir/attention" -type f -mmin +1440 -delete 2>/dev/null || true
  printf '%s' "$now" > "$cleanup_marker" 2>/dev/null || true
fi

ctx=""
msg=""

if [[ -n "$git_abs_dir" && -n "$git_common_dir" && "$git_abs_dir" != "$git_common_dir" ]]; then
  ctx="Worktree session active: branch=${branch}, repo=${repo}. Isolation confirmed. Commit each logical change atomically with selective staging."
  msg="[git-workflow] Worktree active (branch: ${branch}). Isolation confirmed."
else
  linked_wts=$(git worktree list 2>/dev/null | tail -n +2 || true)
  if [[ -n "$linked_wts" ]]; then
    ctx+="Existing worktrees may contain open work: ${linked_wts}. "
  fi
  ctx+="Main worktree (branch: ${branch}). Create and enter an isolated worktree before editing tracked files. The Codex worktree guard blocks apply_patch edits from the main worktree."
  msg="[git-workflow] Main worktree (branch: ${branch}). Use an isolated worktree before edits."
fi

if [[ "${CODEX_GIT_WORKFLOW:-}" == "no-pr" ]]; then
  ctx+=" MODE: no-pr. After committing, run the Codex no-PR review loop in ~/.codex/docs/no-pr-review.md, then merge to ${main_branch} and push. No PR."
  msg+=" MODE: no-pr"
fi

emit_context "$ctx" "$msg"
