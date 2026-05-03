#!/usr/bin/env bash
# Codex PreToolUse hook for Bash: enforce command and git workflow safety.
set -euo pipefail

input=$(cat)
command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // ""' 2>/dev/null || true)
event_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
git_cwd="${event_cwd:-$PWD}"
[[ -n "$command_text" ]] || exit 0

deny() {
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
  printf '(^|[[:space:];|&])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+%s([[:space:]]|$)' "$subcmd"
}

has_git_subcommand() {
  local subcmd="$1" pattern
  pattern=$(git_subcommand_pattern "$subcmd")
  [[ "$command_text" =~ $pattern ]]
}

block_sensitive_paths

if [[ "$command_text" =~ (^|[[:space:]])codex[[:space:]]+execpolicy[[:space:]]+check[[:space:]] ]]; then
  exit 0
fi

[[ "$command_text" =~ (^|[[:space:];|&])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]] ]] || exit 0

git_invocation_count=$(grep -Eo '(^|[[:space:];|&])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+' <<<"$command_text" | wc -l | tr -d ' ')
if (( git_invocation_count > 1 )) && {
  has_git_subcommand "add" ||
  has_git_subcommand "commit" ||
  has_git_subcommand "push" ||
  has_git_subcommand "merge" ||
  has_git_subcommand "rebase" ||
  has_git_subcommand "cherry-pick"
}; then
  deny "BLOCKED: Run one git write operation per command so workflow hooks can validate the exact git context."
fi

if [[ "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+add[[:space:]]+(-A|--all|--update|-u|\.(\ |$)) ]]; then
  deny "BLOCKED: Stage specific files instead of everything. Use: git add <file1> <file2> ..."
fi

if has_git_subcommand "commit"; then
  cmd_no_msg=$(printf '%s' "$command_text" | sed 's/ -m ["'"'"'$].*//')
  if [[ "$cmd_no_msg" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit[[:space:]]+.*(-a(\ |$)|-am(\ |$)|--all) ]]; then
    deny "BLOCKED: Do not use git commit -a. Stage specific files first, then commit."
  fi
fi

branch=""
main_branch="main"
effective_git_cwd=$(git_cwd_from_command "$command_text")
if git -C "$effective_git_cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$effective_git_cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  remote_head=$(git -C "$effective_git_cwd" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
  main_branch="${remote_head#refs/remotes/origin/}"
  main_branch="${main_branch:-main}"
fi
workflow="${CODEX_GIT_WORKFLOW:-}"
if [[ -z "$workflow" ]]; then
  config_path="${CODEX_HOME:-$HOME/.codex}/config.toml"
  if [[ -r "$config_path" ]] && grep -Fq 'CODEX_GIT_WORKFLOW = "no-pr"' "$config_path"; then
    workflow="no-pr"
  fi
fi


if has_git_subcommand "commit" && [[ "$branch" == "$main_branch" ]]; then
  deny "BLOCKED: Cannot commit directly on ${main_branch}. Create and enter an isolated worktree first."
fi

if has_git_subcommand "rebase"; then
  deny "BLOCKED: Rebase is disabled for this workflow. Use merge commits."
fi

if has_git_subcommand "cherry-pick"; then
  deny "BLOCKED: Cherry-pick is disabled for this workflow. Use a feature branch and merge commit."
fi

if [[ "$workflow" != "no-pr" ]] && has_git_subcommand "merge" && [[ "$branch" == "$main_branch" ]]; then
  deny "BLOCKED: Cannot merge/rebase/cherry-pick directly on ${main_branch}. Push a feature branch and use the PR workflow."
fi

if has_git_subcommand "push"; then
  block_push=false
  upstream_main_tracking=false

  if [[ "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+(--delete|-d)[[:space:]]+([^[:space:]]+) ]]; then
    delete_target="${BASH_REMATCH[4]}"
    [[ "$delete_target" != "$main_branch" ]] && exit 0
  fi

  if [[ "$branch" == "$main_branch" && "$workflow" != "no-pr" ]]; then
    if [[ "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+origin[[:space:]]+([^[:space:]]+) ]]; then
      dest="${BASH_REMATCH[4]}"
      [[ "$dest" == "$main_branch" || "$dest" =~ :${main_branch}$ ]] && block_push=true
    else
      block_push=true
    fi
  fi

  if [[ "$block_push" != "true" && "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+origin[[:space:]]+([^[:space:]]+:)?(${main_branch})([[:space:]]|$) ]]; then
    [[ "$workflow" != "no-pr" || "$branch" != "$main_branch" ]] && block_push=true
  fi

  if [[ "$block_push" != "true" && "$branch" != "$main_branch" ]]; then
    upstream_ref=$(git -C "$effective_git_cwd" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null || true)
    if [[ "$upstream_ref" == "origin/${main_branch}" ]]; then
      if [[ "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+origin[[:space:]]+([^[:space:]]+:[^[:space:]]+) ]]; then
        dest_refspec="${BASH_REMATCH[4]}"
        [[ "$dest_refspec" =~ :${main_branch}$ ]] && block_push=true
      else
        block_push=true
        upstream_main_tracking=true
      fi
    fi
  fi

  if [[ "$block_push" == "true" ]]; then
    if [[ "$upstream_main_tracking" == "true" ]]; then
      deny "BLOCKED: Branch ${branch} tracks origin/${main_branch}; use an explicit non-main refspec such as git push origin HEAD:${branch}."
    fi
    deny "BLOCKED: Cannot push directly to ${main_branch}. Push to an explicit feature branch refspec."
  fi
fi

if has_git_subcommand "commit" && git -C "$effective_git_cwd" rev-parse --git-dir >/dev/null 2>&1; then
  staged=$(git -C "$effective_git_cwd" diff --cached --name-only 2>/dev/null || true)
  if [[ -n "$staged" ]]; then
    file_count=$(printf '%s\n' "$staged" | wc -l | tr -d ' ')
    dirs=$(printf '%s\n' "$staged" | awk -F/ 'NF > 1 { seen[$1]=1 } END { for (d in seen) printf "%s%s", sep, d; sep=", " }')
    ctx="Staged files (${file_count}): ${staged}. Verify this is one logical change and use a conventional commit."
    [[ -n "$dirs" ]] && ctx+=" Top-level directories: ${dirs}."
    jq -cn --arg ctx "$ctx" '{systemMessage: $ctx}'
  fi
fi
