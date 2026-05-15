#!/usr/bin/env bash
# Codex PreToolUse hook: enforce atomic staging habits for git commits.
set -euo pipefail

input="$(cat)"
command_text="$(jq -r '.tool_input.command // .tool_input.cmd // ""' <<<"$input")"

if [[ -z "$command_text" ]]; then
  exit 0
fi

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

git_prefix='(^|[[:space:]]*(;|&&|\|\|)[[:space:]]*)git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+'

if [[ "$command_text" =~ ${git_prefix}add([[:space:]]+[^[:space:];&|]+)*[[:space:]]+(-A|--all|--update|-u)([[:space:]]|$|[;&|]) ]]; then
  deny "Broad git add flags and dot pathspecs are disallowed; stage explicit files instead."
fi

if [[ "$command_text" =~ ${git_prefix}add([[:space:]]+[^[:space:];&|]+)*[[:space:]]+\.([[:space:]]|$|[;&|]) ]]; then
  deny "Broad git add flags and dot pathspecs are disallowed; stage explicit files instead."
fi

if [[ "$command_text" =~ ${git_prefix}commit([[:space:]]+[^[:space:];&|]+)*[[:space:]]+(--all|-[^-[:space:];&|]*a[^[:space:];&|]*)([[:space:]]|$|[;&|]) ]]; then
  deny "Avoid commit-all flags; stage explicit files before committing."
fi
