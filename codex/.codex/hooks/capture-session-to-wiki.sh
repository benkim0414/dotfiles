#!/usr/bin/env bash
# Codex Stop hook: write a session capture stub into the wiki vault.
set -euo pipefail

wiki_vault="${WIKI_VAULT:-$HOME/workspace/wiki}"
captures_dir="${wiki_vault}/raw/captures"
log_file="$HOME/.codex/logs/wiki-capture.log"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

log_msg() {
  printf '[%s] wiki-capture: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$log_file" 2>/dev/null || true
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

[[ -n "$session_id" ]] || exit 0

turns=0
tool_calls=0
duration_min=0
if [[ -n "$transcript" && -f "$transcript" ]]; then
  turns=$(wc -l < "$transcript" 2>/dev/null | tr -d ' ' || echo 0)
  tool_calls=$(grep -c '"tool' "$transcript" 2>/dev/null || echo 0)
  first_ts=$(grep -m1 -o '"timestamp":"[^"]*"' "$transcript" 2>/dev/null | sed 's/"timestamp":"//;s/"$//' || true)
  last_ts=$(grep -o '"timestamp":"[^"]*"' "$transcript" 2>/dev/null | tail -1 | sed 's/"timestamp":"//;s/"$//' || true)
  if [[ -n "$first_ts" && -n "$last_ts" ]]; then
    ts0=$(date -d "$first_ts" +%s 2>/dev/null || echo 0)
    ts1=$(date -d "$last_ts" +%s 2>/dev/null || echo 0)
    (( ts0 > 0 && ts1 > ts0 )) && duration_min=$(( (ts1 - ts0) / 60 ))
  fi
fi

if (( tool_calls < 1 && turns < 4 )); then
  exit 0
fi

today=$(date +%Y-%m-%d)
branch=$(git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
slug_source="${last_message:-codex-session-${session_id}}"
slug=$(printf '%s' "$slug_source" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:] ' ' ' | tr -s ' ' | head -c 60 | sed 's/ /-/g;s/^-//;s/-$//')
[[ -n "$slug" ]] || slug="codex-session-${session_id:0:8}"

mkdir -p "$captures_dir"
existing=$(grep -rl "session_id: ${session_id}" "$captures_dir" 2>/dev/null | head -1 || true)
if [[ -n "$existing" ]]; then
  out="$existing"
else
  out="${captures_dir}/${today}--${slug}--codex-session.md"
fi

{
  printf '%s\n' '---'
  printf 'type: capture\nsource: codex-session\ncreated: %s\nsession_id: %s\ncwd: %s\nbranch: %s\ntrigger: %s\n' \
    "$today" "$session_id" "${cwd:-unknown}" "$branch" "$hook_event"
  [[ -n "$transcript" ]] && printf 'transcript: %s\n' "$transcript"
  printf 'duration_min: %s\nturns: %s\ntool_calls: %s\n' "$duration_min" "$turns" "$tool_calls"
  printf '%s\n\n' '---'
  printf '# Session capture: %s\n\n' "$slug"
  printf '**Last assistant message:** %s\n\n' "${last_message:-unknown}"
  printf 'To curate, inspect the transcript and promote durable learnings into the wiki.\n'
} > "$out"

log_msg "wrote $(basename "$out") (turns=${turns}, tool_calls=${tool_calls}, duration=${duration_min}min)"
