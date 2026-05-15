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

is_space() {
  [[ "$1" == " " || "$1" == $'\t' || "$1" == $'\r' ]]
}

inspect_git_words() {
  local -n words_ref=$1
  local index=0
  local subcommand
  local arg
  local skip_next_commit_value=0

  if ((${#words_ref[@]} == 0)) || [[ "${words_ref[0]}" != "git" ]]; then
    return
  fi

  if [[ "${words_ref[1]-}" == "-C" ]]; then
    index=2
  fi

  subcommand="${words_ref[index + 1]-}"
  case "$subcommand" in
    add)
      for arg in "${words_ref[@]:index + 2}"; do
        if [[ "$arg" == "--all" || "$arg" == "--update" || "$arg" =~ ^-[^-[:space:]]*[Au][^[:space:]]*$ ]]; then
          deny "Broad git add flags and dot pathspecs are disallowed; stage explicit files instead."
        fi

        if [[ "$arg" == "." || "$arg" == "./" ]]; then
          deny "Broad git add flags and dot pathspecs are disallowed; stage explicit files instead."
        fi
      done
      ;;
    commit)
      for arg in "${words_ref[@]:index + 2}"; do
        if ((skip_next_commit_value)); then
          skip_next_commit_value=0
          continue
        fi

        case "$arg" in
          -m|--message|-F|--file)
            skip_next_commit_value=1
            continue
            ;;
          --message=*|--file=*)
            continue
            ;;
        esac

        if [[ "$arg" == "--all" || "$arg" =~ ^-[^-[:space:]]*a[^[:space:]]*$ ]]; then
          deny "Avoid commit-all flags; stage explicit files before committing."
        fi
      done
      ;;
  esac
}

scan_dollar_substitution() {
  local text="$1"
  local start="$2"
  local depth=1
  local quote=""
  local ch
  local next
  local i

  SCAN_INNER=""
  SCAN_END=$((start + 1))

  for ((i = start + 2; i < ${#text}; i++)); do
    ch="${text:i:1}"
    next="${text:i+1:1}"

    if [[ -n "$quote" ]]; then
      if [[ "$quote" == '"' && "$ch" == "\\" ]]; then
        ((i++))
        continue
      fi

      if [[ "$ch" == "$quote" ]]; then
        quote=""
      fi
      continue
    fi

    if [[ "$ch" == "'" || "$ch" == '"' ]]; then
      quote="$ch"
      continue
    fi

    if [[ "$ch" == "$" && "$next" == "(" ]]; then
      ((depth++))
      ((i++))
      continue
    fi

    if [[ "$ch" == ")" ]]; then
      ((depth--))
      if ((depth == 0)); then
        SCAN_INNER="${text:start + 2:i - start - 2}"
        SCAN_END="$i"
        return
      fi
    fi
  done

  SCAN_INNER="${text:start + 2}"
  SCAN_END=$((${#text} - 1))
}

scan_backtick_substitution() {
  local text="$1"
  local start="$2"
  local ch
  local next
  local i

  SCAN_INNER=""
  SCAN_END="$start"

  for ((i = start + 1; i < ${#text}; i++)); do
    ch="${text:i:1}"
    next="${text:i+1:1}"

    if [[ "$ch" == "\\" && "$next" == "\`" ]]; then
      ((i++))
      continue
    fi

    if [[ "$ch" == "\`" ]]; then
      SCAN_INNER="${text:start + 1:i - start - 1}"
      SCAN_END="$i"
      return
    fi
  done

  SCAN_INNER="${text:start + 1}"
  SCAN_END=$((${#text} - 1))
}

scan_shell_commands() {
  local text="$1"
  local -a words=()
  local word=""
  local in_word=0
  local quote=""
  local ch
  local next
  local i

  finish_word() {
    if ((in_word)); then
      words+=("$word")
      word=""
      in_word=0
    fi
  }

  finish_command() {
    finish_word
    inspect_git_words words
    words=()
  }

  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    next="${text:i+1:1}"

    if [[ -n "$quote" ]]; then
      if [[ "$quote" == '"' && "$ch" == "\\" ]]; then
        in_word=1
        if [[ -n "$next" ]]; then
          word+="$next"
          ((i++))
        fi
        continue
      fi

      if [[ "$quote" == '"' && "$ch" == "$" && "$next" == "(" ]]; then
        scan_dollar_substitution "$text" "$i"
        scan_shell_commands "$SCAN_INNER"
        i="$SCAN_END"
        in_word=1
        continue
      fi

      if [[ "$quote" == '"' && "$ch" == "\`" ]]; then
        scan_backtick_substitution "$text" "$i"
        scan_shell_commands "$SCAN_INNER"
        i="$SCAN_END"
        in_word=1
        continue
      fi

      if [[ "$ch" == "$quote" ]]; then
        quote=""
        in_word=1
        continue
      fi

      word+="$ch"
      in_word=1
      continue
    fi

    if is_space "$ch"; then
      finish_word
      continue
    fi

    case "$ch" in
      "'")
        quote="'"
        in_word=1
        ;;
      '"')
        quote='"'
        in_word=1
        ;;
      "\\")
        in_word=1
        if [[ -n "$next" ]]; then
          word+="$next"
          ((i++))
        fi
        ;;
      $'\n'|';'|'|')
        finish_command
        ;;
      '&')
        if [[ "$next" == "&" ]]; then
          finish_command
          ((i++))
        else
          word+="$ch"
          in_word=1
        fi
        ;;
      '$')
        if [[ "$next" == "(" ]]; then
          scan_dollar_substitution "$text" "$i"
          scan_shell_commands "$SCAN_INNER"
          i="$SCAN_END"
          in_word=1
        else
          word+="$ch"
          in_word=1
        fi
        ;;
      "\`")
        scan_backtick_substitution "$text" "$i"
        scan_shell_commands "$SCAN_INNER"
        i="$SCAN_END"
        in_word=1
        ;;
      *)
        word+="$ch"
        in_word=1
        ;;
    esac
  done

  finish_command
}

scan_shell_commands "$command_text"
