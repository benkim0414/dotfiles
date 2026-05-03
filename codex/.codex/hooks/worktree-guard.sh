#!/usr/bin/env bash
# Codex PreToolUse hook for apply_patch: block tracked-file edits on main.
set -euo pipefail

input=$(cat)

deny() {
  jq -cn --arg reason "BLOCKED: apply_patch edits are not allowed from the main worktree. Create and enter an isolated worktree branch first." '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

abs_path() {
  local base="$1" path="$2"

  if [[ "$path" == /* ]]; then
    realpath -m -- "$path" 2>/dev/null || printf '%s\n' "$path"
  else
    realpath -m -- "${base}/${path}" 2>/dev/null || printf '%s/%s\n' "$base" "$path"
  fi
}

existing_parent() {
  local path="$1" dir
  dir=$(dirname -- "$path")

  while [[ "$dir" != "/" && ! -d "$dir" ]]; do
    dir=$(dirname -- "$dir")
  done

  [[ -d "$dir" ]] && printf '%s\n' "$dir"
}

is_linked_worktree() {
  local cwd="$1" git_abs_dir git_common_raw git_common_dir

  git_abs_dir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null || true)
  git_common_raw=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)
  [[ -n "$git_abs_dir" && -n "$git_common_raw" ]] || return 1

  if [[ "$git_common_raw" == /* ]]; then
    git_common_dir=$(realpath -m -- "$git_common_raw" 2>/dev/null || printf '%s\n' "$git_common_raw")
  else
    git_common_dir=$(realpath -m -- "${cwd}/${git_common_raw}" 2>/dev/null || printf '%s/%s\n' "$cwd" "$git_common_raw")
  fi

  [[ "$git_abs_dir" != "$git_common_dir" ]]
}

main_branch_for() {
  local cwd="$1" remote_head main_branch

  remote_head=$(git -C "$cwd" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
  main_branch="${remote_head#refs/remotes/origin/}"
  printf '%s\n' "${main_branch:-main}"
}

check_git_context() {
  local cwd="$1" branch main_branch

  if ! git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    return 0
  fi

  if is_linked_worktree "$cwd"; then
    return 0
  fi

  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  main_branch=$(main_branch_for "$cwd")

  [[ "$branch" == "$main_branch" ]] && deny
}

event_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
base_cwd="${event_cwd:-$PWD}"
mapfile -t targets < <(
  printf '%s' "$input" | jq -r '
    def patch_text:
      if (.tool_input | type) == "string" then .tool_input
      else (.tool_input.patch? // .tool_input.input? // "")
      end;

    .tool_input as $tool_input |
    (if ($tool_input | type) == "object" then
      ($tool_input.file_path?, $tool_input.path?, $tool_input.notebook_path?) // empty
    else empty end),
    (patch_text | strings | split("\n")[] |
      (try capture("^\\*\\*\\* (?:Add|Update|Delete) File: (?<path>.+)$").path catch empty)),
    (patch_text | strings | split("\n")[] |
      (try capture("^\\*\\*\\* Move to: (?<path>.+)$").path catch empty))
  ' 2>/dev/null | awk 'NF && !seen[$0]++'
)

if (( ${#targets[@]} > 0 )); then
  for target in "${targets[@]}"; do
    resolved=$(abs_path "$base_cwd" "$target")
    parent=$(existing_parent "$resolved")
    [[ -n "$parent" ]] && check_git_context "$parent"
  done
  exit 0
fi

check_git_context "$base_cwd"
