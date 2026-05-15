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

git_prefix='(^|[[:space:];&])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+'

if [[ "$command_text" =~ ${git_prefix}add[[:space:]]+(-A|--all|--update|-u|--[[:space:]]+\.|\.)([[:space:]]|$|[;&]) ]]; then
  deny "Use explicit pathspecs with git add so commits stay focused."
fi

if [[ "$command_text" =~ ${git_prefix}commit([[:space:]]+[^[:space:];&]+)*[[:space:]]+(-a|-am[^[:space:];&]*|--all)([[:space:]]|$|[;&]) ]]; then
  deny "Avoid commit-all flags; stage explicit files before committing."
fi
