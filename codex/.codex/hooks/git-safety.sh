#!/usr/bin/env bash
# Codex PreToolUse hook for Bash: enforce git workflow safety.
set -euo pipefail

input=$(cat)
command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // ""' 2>/dev/null || true)
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

[[ "$command_text" =~ (^|[[:space:]])git[[:space:]] ]] || exit 0

if [[ "$command_text" =~ git[[:space:]]+add[[:space:]]+(-A|--all|--update|-u|\.(\ |$)) ]]; then
  deny "BLOCKED: Stage specific files instead of everything. Use: git add <file1> <file2> ..."
fi

if [[ "$command_text" =~ git[[:space:]]+commit ]]; then
  cmd_no_msg=$(printf '%s' "$command_text" | sed 's/ -m ["'"'"'$].*//')
  if [[ "$cmd_no_msg" =~ git[[:space:]]+commit[[:space:]]+.*(-a(\ |$)|-am(\ |$)|--all) ]]; then
    deny "BLOCKED: Do not use git commit -a. Stage specific files first, then commit."
  fi
fi

branch=""
main_branch="main"
if git rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  remote_head=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
  main_branch="${remote_head#refs/remotes/origin/}"
  main_branch="${main_branch:-main}"
fi

if [[ "$command_text" =~ git[[:space:]]+commit && "$branch" == "$main_branch" ]]; then
  deny "BLOCKED: Cannot commit directly on ${main_branch}. Create and enter an isolated worktree first."
fi

if [[ "${CODEX_GIT_WORKFLOW:-}" != "no-pr" && "$command_text" =~ git[[:space:]]+(merge|rebase|cherry-pick) && "$branch" == "$main_branch" ]]; then
  deny "BLOCKED: Cannot merge/rebase/cherry-pick directly on ${main_branch}. Push a feature branch and use the PR workflow."
fi

if [[ "$command_text" =~ git[[:space:]]+push ]]; then
  block_push=false
  upstream_main_tracking=false

  if [[ "$command_text" =~ git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+(--delete|-d)[[:space:]]+([^[:space:]]+) ]]; then
    delete_target="${BASH_REMATCH[2]}"
    [[ "$delete_target" != "$main_branch" ]] && exit 0
  fi

  if [[ "$branch" == "$main_branch" && "${CODEX_GIT_WORKFLOW:-}" != "no-pr" ]]; then
    if [[ "$command_text" =~ git[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+origin[[:space:]]+([^[:space:]]+) ]]; then
      dest="${BASH_REMATCH[2]}"
      [[ "$dest" == "$main_branch" || "$dest" =~ :${main_branch}$ ]] && block_push=true
    else
      block_push=true
    fi
  fi

  if [[ "$block_push" != "true" && "$command_text" =~ git[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+origin[[:space:]]+([^[:space:]]+:)?(${main_branch})([[:space:]]|$) ]]; then
    [[ "${CODEX_GIT_WORKFLOW:-}" != "no-pr" || "$branch" != "$main_branch" ]] && block_push=true
  fi

  if [[ "$block_push" != "true" && "$branch" != "$main_branch" ]]; then
    upstream_ref=$(git rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null || true)
    if [[ "$upstream_ref" == "origin/${main_branch}" ]]; then
      if [[ "$command_text" =~ git[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+origin[[:space:]]+([^[:space:]]+:[^[:space:]]+) ]]; then
        dest_refspec="${BASH_REMATCH[2]}"
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

if [[ "$command_text" =~ git[[:space:]]+commit ]] && git rev-parse --git-dir >/dev/null 2>&1; then
  staged=$(git diff --cached --name-only 2>/dev/null || true)
  if [[ -n "$staged" ]]; then
    file_count=$(printf '%s\n' "$staged" | wc -l | tr -d ' ')
    dirs=$(printf '%s\n' "$staged" | awk -F/ 'NF > 1 { seen[$1]=1 } END { for (d in seen) printf "%s%s", sep, d; sep=", " }')
    ctx="Staged files (${file_count}): ${staged}. Verify this is one logical change and use a conventional commit."
    [[ -n "$dirs" ]] && ctx+=" Top-level directories: ${dirs}."
    jq -cn --arg ctx "$ctx" '{systemMessage: $ctx}'
  fi
fi
