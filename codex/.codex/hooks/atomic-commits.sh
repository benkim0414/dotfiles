#!/usr/bin/env bash
# Codex PreToolUse hook: enforce atomic staging habits for git commits.
set -euo pipefail

input="$(cat)"
command_text="$(jq -r '.tool_input.command // .tool_input.cmd // ""' <<<"$input")"

if [[ -z "$command_text" ]]; then
  exit 0
fi

mask_quoted_content() {
  local text="$1"
  local result=""
  local quote=""
  local substitution_depth=0
  local backtick_substitution=0
  local ch
  local next
  local i

  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    next="${text:i+1:1}"

    if ((substitution_depth > 0)); then
      if [[ "$ch" == "$" && "$next" == "(" ]]; then
        result+="; "
        ((substitution_depth++))
        ((i++))
        continue
      fi

      if [[ "$ch" == ")" ]]; then
        ((substitution_depth--))
        result+=";"
        continue
      fi

      result+="$ch"
      continue
    fi

    if ((backtick_substitution > 0)); then
      if [[ "$ch" == "\\" && "$next" == "\`" ]]; then
        result+="  "
        ((i++))
        continue
      fi

      if [[ "$ch" == "\`" ]]; then
        backtick_substitution=0
        result+=";"
        continue
      fi

      result+="$ch"
      continue
    fi

    if [[ -n "$quote" ]]; then
      if [[ "$quote" == '"' && "$ch" == "\\" ]]; then
        result+=" "
        if [[ -n "$next" ]]; then
          result+=" "
          ((i++))
        fi
        continue
      fi

      if [[ "$quote" == '"' && "$ch" == "$" && "$next" == "(" ]]; then
        result+="; "
        substitution_depth=1
        ((i++))
        continue
      fi

      if [[ "$quote" == '"' && "$ch" == "\`" ]]; then
        result+="; "
        backtick_substitution=1
        continue
      fi

      if [[ "$ch" == "$quote" ]]; then
        quote=""
      fi
      result+=" "
      continue
    fi

    if [[ "$ch" == "'" || "$ch" == '"' ]]; then
      quote="$ch"
      result+=" "
      continue
    fi

    if [[ "$ch" == "\`" ]]; then
      result+="; "
      backtick_substitution=1
      continue
    fi

    if [[ "$ch" == "$" && "$next" == "(" ]]; then
      result+="; "
      substitution_depth=1
      ((i++))
      continue
    fi

    result+="$ch"
  done

  printf '%s' "$result"
}

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

command_for_detection="$(mask_quoted_content "$command_text")"
command_for_detection="${command_for_detection//$'\n'/;}"
git_prefix='(^|[[:space:]]*(;|&&|\|\||\|)[[:space:]]*)git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+'

if [[ "$command_for_detection" =~ ${git_prefix}add([[:space:]]+[^[:space:];&|]+)*[[:space:]]+(--all|--update|-[^-[:space:];&|]*[Au][^[:space:];&|]*)([[:space:]]|$|[;&|]) ]]; then
  deny "Broad git add flags and dot pathspecs are disallowed; stage explicit files instead."
fi

if [[ "$command_for_detection" =~ ${git_prefix}add([[:space:]]+[^[:space:];&|]+)*[[:space:]]+\.(/)?([[:space:]]|$|[;&|]) ]]; then
  deny "Broad git add flags and dot pathspecs are disallowed; stage explicit files instead."
fi

if [[ "$command_for_detection" =~ ${git_prefix}commit([[:space:]]+[^[:space:];&|]+)*[[:space:]]+(--all|-[^-[:space:];&|]*a[^[:space:];&|]*)([[:space:]]|$|[;&|]) ]]; then
  deny "Avoid commit-all flags; stage explicit files before committing."
fi
