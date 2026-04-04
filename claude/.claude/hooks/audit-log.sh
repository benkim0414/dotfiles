#!/usr/bin/env bash
# PostToolUse hook: append a JSONL audit entry for every mutating tool call.
# Runs async — must never block Claude Code.
set -euo pipefail

# shellcheck source=../lib/portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/portability.sh"

INPUT=$(cat)

# --- Parse fields with a single jq call ---
IFS=$'\t' read -r TOOL SESSION_ID CWD COMMAND FILE_PATH DESCRIPTION <<< "$(
  printf '%s' "$INPUT" | jq -r '[
    (.tool_name // ""),
    (.session_id // ""),
    (.cwd // ""),
    ((.tool_input.command // "") | gsub("\n"; "\\n") | .[0:500]),
    (.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // ""),
    (.tool_input.description // "")
  ] | @tsv'
)"

# --- Determine log directory and file ---
LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
chmod 700 "$LOG_DIR" 2>/dev/null || true
TODAY=$(date -u +%Y-%m-%d)
LOG_FILE="${LOG_DIR}/audit-${TODAY}.log"

# --- Size guard: rotate if file exceeds 50 MB ---
MAX_BYTES=52428800
if [[ -f "$LOG_FILE" ]]; then
  SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if (( SIZE > MAX_BYTES )); then
    N=1
    while [[ -f "${LOG_FILE}.${N}" ]]; do
      N=$((N + 1))
    done
    mv "$LOG_FILE" "${LOG_FILE}.${N}" 2>/dev/null || true
  fi
fi

# --- Build summary field based on tool type ---
SUMMARY=""
case "$TOOL" in
  Bash)          SUMMARY="$COMMAND" ;;
  Write)         SUMMARY="write ${FILE_PATH}" ;;
  Edit|MultiEdit) SUMMARY="edit ${FILE_PATH}" ;;
  NotebookEdit)  SUMMARY="notebook-edit ${FILE_PATH}" ;;
esac

# --- Truncated output snippet (first 200 chars of tool_output) ---
OUTPUT_SNIPPET=$(printf '%s' "$INPUT" | jq -r '
  (.tool_output // "") | tostring | .[0:200]
')

# --- Build and append JSON log entry (single printf for atomic write) ---
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENTRY=$(jq -n -c \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg tool "$TOOL" \
  --arg cwd "$CWD" \
  --arg summary "$SUMMARY" \
  --arg desc "$DESCRIPTION" \
  --arg output "$OUTPUT_SNIPPET" \
  '{
    timestamp: $ts,
    session_id: $sid,
    tool: $tool,
    cwd: $cwd,
    summary: $summary,
    description: $desc,
    output_snippet: $output
  }') || true
[[ -n "$ENTRY" ]] && printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true

exit 0
