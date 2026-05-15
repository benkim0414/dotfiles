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

find_git_subcommand_index() {
  local -n git_words_ref=$1
  local i=1
  local arg

  while ((i < ${#git_words_ref[@]})); do
    arg="${git_words_ref[i]}"

    case "$arg" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env)
        ((i += 2))
        ;;
      --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--super-prefix=*|--config-env=*)
        ((i++))
        ;;
      --bare|--no-pager|--literal-pathspecs|--no-optional-locks|--no-replace-objects|--paginate)
        ((i++))
        ;;
      *)
        GIT_SUBCOMMAND_INDEX="$i"
        return
        ;;
    esac
  done

  GIT_SUBCOMMAND_INDEX="$i"
}

inspect_git_words() {
  local -n words_ref=$1
  local git_index=-1
  local i
  local j
  local prefixes_are_safe
  local subcommand_index
  local subcommand
  local arg
  local skip_next_commit_value=0

  for ((i = 0; i < ${#words_ref[@]}; i++)); do
    if [[ "${words_ref[i]}" != "git" ]]; then
      continue
    fi

    prefixes_are_safe=1
    for ((j = 0; j < i; j++)); do
      case "${words_ref[j]}" in
        '('|'{'|then|do|else|command|time)
          ;;
        *)
          prefixes_are_safe=0
          break
          ;;
      esac
    done

    if ((prefixes_are_safe)); then
      git_index="$i"
      break
    fi
  done

  if ((git_index < 0)); then
    return
  fi

  local -a git_words=("${words_ref[@]:git_index}")

  find_git_subcommand_index git_words
  subcommand_index="$GIT_SUBCOMMAND_INDEX"

  subcommand="${git_words[subcommand_index]-}"
  case "$subcommand" in
    add)
      for arg in "${git_words[@]:subcommand_index + 1}"; do
        if [[ "$arg" == "--all" || "$arg" == "--update" || "$arg" == "--pathspec-from-file" || "$arg" == --pathspec-from-file=* || "$arg" == "--pathspec-file-nul" || "$arg" =~ ^-[^-[:space:]]*[Au][^[:space:]]*$ ]]; then
          deny "Broad git add flags and pathspecs are disallowed; stage explicit files instead."
        fi

        if [[ "$arg" == "." || "$arg" == "./" || "$arg" == ":/" || "$arg" == ":" || "$arg" == ":(top)" || "$arg" == *"*"* || "$arg" == *"?"* || "$arg" == *"["* ]]; then
          deny "Broad git add flags and pathspecs are disallowed; stage explicit files instead."
        fi
      done
      ;;
    commit)
      for arg in "${git_words[@]:subcommand_index + 1}"; do
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
      '('|')'|'{'|'}')
        finish_command
        ;;
      $'\n'|';')
        finish_command
        ;;
      '|')
        finish_command
        if [[ "$next" == "&" ]]; then
          ((i++))
        fi
        ;;
      '&')
        if [[ "$next" == "&" ]]; then
          ((i++))
        fi
        finish_command
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
