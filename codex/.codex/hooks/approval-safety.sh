#!/usr/bin/env bash
# Codex approval hook: auto-allow worktree-local approvals, keep main merge gated.
set -euo pipefail

input=$(cat)
hook_event=$(printf '%s' "$input" | jq -r '.hook_event_name // .hookEventName // empty' 2>/dev/null || true)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // ""' 2>/dev/null || true)
event_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
git_cwd="${event_cwd:-$PWD}"

[[ -n "$hook_event" ]] || hook_event="PreToolUse"

allow_permission() {
  jq -cn '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: { behavior: "allow" }
    }
  }'
  exit 0
}

deny_pretool() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

deny_permission() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: { behavior: "deny", message: $reason }
    }
  }'
  exit 0
}

deny() {
  local reason="$1"
  if [[ "$hook_event" == "PermissionRequest" ]]; then
    deny_permission "$reason"
  fi
  deny_pretool "$reason"
}

shell_quote() {
  local raw="$1"
  printf '%q' "$raw"
}

literal_path_patterns() {
  local path="$1" quoted
  quoted=$(shell_quote "$path")
  printf '%s\n' "$path" "$quoted"
}

block_sensitive_paths() {
  local path pattern
  local paths=(
    "$HOME/.ssh/"
    "$HOME/.gnupg/"
    "$HOME/.aws/credentials"
    "$HOME/.kube/config"
    "$HOME/.docker/config.json"
    "$HOME/.netrc"
    "$HOME/.config/gh/hosts.yml"
  )

  for path in "${paths[@]}"; do
    while IFS= read -r pattern; do
      [[ -n "$pattern" ]] || continue
      if [[ "$path" == */ && "$command_text" == *"$pattern"* ]]; then
        deny "BLOCKED: Command references sensitive path ${path}."
      fi
      if [[ "$path" != */ && "$command_text" == *"$pattern"* ]]; then
        deny "BLOCKED: Command references sensitive file ${path}."
      fi
    done < <(literal_path_patterns "$path")
  done

  case "$command_text" in
    *'~/.ssh/'*|*'~/.gnupg/'*|*'~/.aws/credentials'*|*'~/.kube/config'*|*'~/.docker/config.json'*|*'~/.netrc'*|*'~/.config/gh/hosts.yml'*)
      deny "BLOCKED: Command references a sensitive home-directory path."
      ;;
  esac
}

git_cwd_from_command() {
  local cmd="$1"

  if [[ "$cmd" =~ (^|[[:space:]])git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]//\'/}"
    return 0
  fi

  printf '%s\n' "$git_cwd"
}

git_subcommand_pattern() {
  local subcmd="$1"
  printf '(^|[[:space:];&])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+%s([[:space:]]|$)' "$subcmd"
}

has_git_subcommand() {
  local subcmd="$1" pattern
  pattern=$(git_subcommand_pattern "$subcmd")
  [[ "$command_text" =~ $pattern ]]
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

matches_worktree_allowed_command() {
  [[ "$command_text" =~ (^|[[:space:];&])rm[[:space:]]+-rf([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])sudo([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])kubectl[[:space:]]+delete([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])terraform[[:space:]]+destroy([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])helm[[:space:]]+uninstall([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])docker[[:space:]]+(rm|rmi)([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])docker[[:space:]]+system[[:space:]]+prune([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])docker[[:space:]]+volume[[:space:]]+rm([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])docker[[:space:]]+network[[:space:]]+rm([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])pip[[:space:]]+install([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])npm[[:space:]]+install[[:space:]]+-g([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])cargo[[:space:]]+install([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])go[[:space:]]+install([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+repo[[:space:]]+(delete|archive)([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+release[[:space:]]+delete([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+issue[[:space:]]+(close|lock|delete)([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+run[[:space:]]+cancel([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+workflow[[:space:]]+disable([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+cache[[:space:]]+delete([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+secret[[:space:]]+delete([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+variable[[:space:]]+delete([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+label[[:space:]]+delete([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+api[[:space:]]+--method[[:space:]]+DELETE([[:space:]]|$) ]] && return 0
  [[ "$command_text" =~ (^|[[:space:];&])gh[[:space:]]+api[[:space:]]+-X[[:space:]]+DELETE([[:space:]]|$) ]] && return 0

  has_git_subcommand "reset" && [[ "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+reset[[:space:]]+--hard ]] && return 0
  has_git_subcommand "clean" && [[ "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+clean[[:space:]]+-f ]] && return 0
  has_git_subcommand "branch" && [[ "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+branch[[:space:]]+-D ]] && return 0
  has_git_subcommand "push" && [[ "$command_text" =~ (^|[[:space:]])(-f|--force|--force-with-lease)([[:space:]]|$) ]] && return 0
  has_git_subcommand "merge" && return 0

  return 1
}

[[ -n "$command_text" ]] || exit 0
[[ "$tool_name" == "Bash" || -z "$tool_name" ]] || exit 0

block_sensitive_paths

effective_git_cwd=$(git_cwd_from_command "$command_text")
linked_worktree=false
branch=""
main_branch="main"
if git -C "$effective_git_cwd" rev-parse --git-dir >/dev/null 2>&1; then
  is_linked_worktree "$effective_git_cwd" && linked_worktree=true
  branch=$(git -C "$effective_git_cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  main_branch=$(main_branch_for "$effective_git_cwd")
fi

if has_git_subcommand "merge"; then
  if [[ "$branch" == "$main_branch" && "$linked_worktree" != "true" ]]; then
    exit 0
  fi
  if [[ "$hook_event" == "PermissionRequest" && "$linked_worktree" == "true" ]]; then
    allow_permission
  fi
  exit 0
fi

matches_worktree_allowed_command || exit 0

if [[ "$linked_worktree" == "true" ]]; then
  if [[ "$hook_event" == "PermissionRequest" ]]; then
    allow_permission
  fi
  exit 0
fi

deny "BLOCKED: Approval-sensitive commands must run from an isolated worktree; only the final merge into main should ask for approval."
