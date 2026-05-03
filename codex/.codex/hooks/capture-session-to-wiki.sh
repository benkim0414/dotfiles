#!/usr/bin/env bash
# Codex Stop hook: write a structured session capture into the wiki vault.
set -euo pipefail

wiki_vault="${WIKI_VAULT:-$HOME/workspace/wiki}"
captures_dir="${wiki_vault}/raw/captures"
log_file="$HOME/.codex/logs/wiki-capture.log"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

log_msg() {
  [[ -w "$(dirname "$log_file")" ]] || return 0
  printf '[%s] wiki-capture: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$log_file" 2>/dev/null || true
}

yaml_scalar() {
  printf '%s' "$1" | sed 's/"/\\"/g; s/^/"/; s/$/"/'
}

frontmatter_list() {
  local name="$1"
  local raw="$2"
  local item

  [[ -n "$raw" ]] || return 0
  printf '%s:\n' "$name"
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    printf '  - %s\n' "$(yaml_scalar "$item")"
  done <<< "$raw"
}

body_list() {
  local raw="$1"
  local item

  if [[ -z "$raw" ]]; then
    printf -- '- none\n'
    return 0
  fi

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    printf -- "- \`%s\`\n" "$item"
  done <<< "$raw"
}

if [[ ! -d "$wiki_vault" ]] || ! git -C "$wiki_vault" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
hook_event=$(printf '%s' "$input" | jq -r '.hook_event_name // "Stop"' 2>/dev/null || true)
last_message=$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)

[[ "$session_id" =~ ^[A-Za-z0-9._:-]+$ ]] || exit 0

turns=0
user_turns=0
tool_calls=0
duration_min=0
first_prompt=""
last_prompt=""
assistant_summary="$last_message"
tools_used=""
commands_run=""
files_touched=""
codex_cli_version=""

if [[ -n "$transcript" && -f "$transcript" ]]; then
  parsed=$(
    jq -rn '
      def text_content:
        (.payload.content // [])
        | arrays
        | map(select((.type // "") == "input_text" or (.type // "") == "output_text") | (.text // ""))
        | map(select(length > 0))
        | join("\n\n");

      def real_user_text:
        select(.type == "response_item")
        | select(.payload.type == "message" and .payload.role == "user")
        | (.payload.content // [])
        | arrays
        | .[]
        | select((.type // "") == "input_text")
        | (.text // "")
        | select(length > 0)
        | select(startswith("# AGENTS.md instructions") | not)
        | select(startswith("<environment_context>") | not)
        | select(startswith("<permissions instructions>") | not)
        | select(startswith("<collaboration_mode>") | not)
        | select(startswith("<skills_instructions>") | not)
        | select(startswith("Existing worktrees may contain open work:") | not)
        | select(startswith("This session is being continued") | not)
        | select(startswith("Warning: apply_patch was requested via exec_command.") | not);

      def arg_object:
        if . == null then {}
        elif type == "string" then (try fromjson catch {})
        elif type == "object" then .
        else {}
        end;

      def arg_text:
        if . == null then ""
        elif type == "string" then .
        else tostring
        end;

      def patch_files:
        split("\n")
        | map(select(test("^\\*\\*\\* (Add|Update|Delete) File: "))
          | sub("^\\*\\*\\* (Add|Update|Delete) File: "; ""))
        | map(select(length > 0));

      def command_summary:
        .payload.arguments
        | arg_object
        | (.cmd // .command // "")
        | gsub("\n"; "\\n")
        | .[0:240];

      [inputs] as $lines |
      ($lines | length) as $turns |
      ($lines | map(select(.type == "session_meta") | .payload.cli_version // "") | map(select(length > 0)) | .[0] // "") as $cli |
      ($lines | map(select(.timestamp != null) | .timestamp)) as $timestamps |
      ($lines | map(real_user_text)) as $prompts |
      ($lines | map(
        select(.type == "response_item")
        | select(.payload.type == "message" and .payload.role == "assistant")
        | text_content
        | select(length > 0)
      )) as $assistant_messages |
      ($lines | map(select(.type == "response_item" and .payload.type == "function_call"))) as $tool_events |
      ($tool_events | map(.payload.name // "") | map(select(length > 0)) | unique | join("\n")) as $tools |
      ($tool_events | map(select((.payload.name // "") == "exec_command") | command_summary) | map(select(length > 0)) | unique | .[0:20] | join("\n")) as $commands |
      ($tool_events | map(select((.payload.name // "") == "apply_patch") | (.payload.arguments | arg_text | patch_files)) | flatten | unique | join("\n")) as $files |
      [
        $turns,
        ($prompts | length),
        ($tool_events | length),
        ($prompts[0] // "" | .[0:500]),
        ($prompts[-1] // "" | .[0:500]),
        ($assistant_messages[-1] // "" | .[0:1200]),
        $tools,
        $commands,
        $files,
        $cli,
        ($timestamps[0] // ""),
        ($timestamps[-1] // "")
      ] | @json
    ' "$transcript" 2>/dev/null || true
  )

  if [[ -n "$parsed" ]]; then
    turns=$(printf '%s' "$parsed" | jq -r '.[0] // 0')
    user_turns=$(printf '%s' "$parsed" | jq -r '.[1] // 0')
    tool_calls=$(printf '%s' "$parsed" | jq -r '.[2] // 0')
    first_prompt=$(printf '%s' "$parsed" | jq -r '.[3] // ""')
    last_prompt=$(printf '%s' "$parsed" | jq -r '.[4] // ""')
    assistant_summary=$(printf '%s' "$parsed" | jq -r '.[5] // ""')
    tools_used=$(printf '%s' "$parsed" | jq -r '.[6] // ""')
    commands_run=$(printf '%s' "$parsed" | jq -r '.[7] // ""')
    files_touched=$(printf '%s' "$parsed" | jq -r '.[8] // ""')
    codex_cli_version=$(printf '%s' "$parsed" | jq -r '.[9] // ""')
    first_ts=$(printf '%s' "$parsed" | jq -r '.[10] // ""')
    last_ts=$(printf '%s' "$parsed" | jq -r '.[11] // ""')

    if [[ -n "$first_ts" && -n "$last_ts" ]]; then
      ts0=$(date -d "$first_ts" +%s 2>/dev/null || echo 0)
      ts1=$(date -d "$last_ts" +%s 2>/dev/null || echo 0)
      (( ts0 > 0 && ts1 > ts0 )) && duration_min=$(( (ts1 - ts0) / 60 ))
    fi
  fi
fi

if (( tool_calls < 1 && user_turns < 1 )); then
  exit 0
fi

today=$(date +%Y-%m-%d)
branch=$(git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
slug_source="${first_prompt:-codex-session-${session_id}}"
slug=$(printf '%s' "$slug_source" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:] ' ' ' | tr -s ' ' | head -c 60 | sed 's/ /-/g;s/^-//;s/-$//')
[[ -n "$slug" ]] || slug="codex-session-${session_id:0:8}"

mkdir -p "$captures_dir"
existing=$(grep -F -rl "session_id: ${session_id}" "$captures_dir" 2>/dev/null | head -1 || true)
if [[ -z "$existing" ]]; then
  existing=$(grep -F -rl "session_id: \"${session_id}\"" "$captures_dir" 2>/dev/null | head -1 || true)
fi
if [[ -n "$existing" ]]; then
  out="$existing"
else
  out="${captures_dir}/${today}--${slug}--codex-session.md"
fi

{
  printf '%s\n' '---'
  printf 'type: capture\nsource: codex-session\ncreated: %s\n' "$today"
  printf 'session_id: %s\ncwd: %s\nbranch: %s\ntrigger: %s\n' \
    "$(yaml_scalar "$session_id")" "$(yaml_scalar "${cwd:-unknown}")" "$(yaml_scalar "$branch")" "$(yaml_scalar "$hook_event")"
  [[ -n "$transcript" ]] && printf 'transcript: %s\n' "$(yaml_scalar "$transcript")"
  [[ -n "$codex_cli_version" ]] && printf 'codex_cli_version: %s\n' "$(yaml_scalar "$codex_cli_version")"
  printf 'duration_min: %s\nturns: %s\nuser_turns: %s\ntool_calls: %s\n' "$duration_min" "$turns" "$user_turns" "$tool_calls"
  frontmatter_list "tools_used" "$tools_used"
  frontmatter_list "files_touched" "$files_touched"
  printf '%s\n\n' '---'
  printf '# Session capture: %s\n\n' "$slug"
  printf '**First prompt:** %s\n\n' "${first_prompt:-unknown}"
  printf '**Last prompt:** %s\n\n' "${last_prompt:-unknown}"
  printf '**Last assistant message:** %s\n\n' "${assistant_summary:-unknown}"
  printf '## Commands observed\n\n'
  body_list "$commands_run"
  printf '\n## Curation notes\n\n'
  printf 'Review the transcript for durable learnings: failures with resolutions, non-obvious command behavior, tool quirks, architecture decisions, or reusable corrections from the user.\n\n'
  printf 'To curate, run the wiki ingest workflow against this raw capture or promote durable learnings into wiki pages manually.\n\n'
  if [[ -n "$transcript" ]]; then
    printf 'To inspect the full transcript:\n    jq -c '\''.'\'' < %s\n' "$transcript"
  fi
} > "$out"

log_msg "wrote $(basename "$out") (turns=${turns}, user_turns=${user_turns}, tool_calls=${tool_calls}, duration=${duration_min}min)"
