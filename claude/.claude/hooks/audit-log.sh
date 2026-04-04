#!/usr/bin/env bash
# PostToolUse hook: append a JSONL audit entry for every mutating tool call.
# Runs async — must never block Claude Code.
set -euo pipefail

# --- Build JSONL entry in a single jq pass (avoids extra process spawns) ---
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENTRY=$(cat | jq -c --arg ts "$TIMESTAMP" '
  # Extract fields
  (.tool_name // "") as $tool |
  (.session_id // "") as $sid |
  (.cwd // "") as $cwd |
  ((.tool_input.command // "") | gsub("\n"; "\\n") | .[0:500]) as $cmd |
  (.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // "") as $path |
  (.tool_input.description // "") as $desc |
  ((.tool_output // "") | tostring | .[0:200]) as $out |

  # Build summary based on tool type
  (.tool_input.url // "") as $url |
  (.tool_input.query // "") as $query |
  (.tool_input | keys_unsorted | join(",")) as $input_keys |
  (if   $tool == "Bash"         then $cmd
   elif $tool == "Write"        then "write \($path)"
   elif $tool == "Edit" or $tool == "MultiEdit" then "edit \($path)"
   elif $tool == "NotebookEdit" then "notebook-edit \($path)"
   elif $tool == "WebFetch"     then "fetch \($url | .[0:200])"
   elif $tool == "WebSearch"    then "search \($query | .[0:200])"
   else "\($tool | ascii_downcase) \($input_keys)" end) as $summary |

  {
    timestamp: $ts,
    session_id: $sid,
    tool: $tool,
    cwd: $cwd,
    summary: $summary,
    description: $desc,
    output_snippet: $out
  }
') || true

[[ -z "$ENTRY" ]] && exit 0

# --- Determine log directory and file ---
LOG_DIR="${HOME}/.claude/logs"
TODAY=$(date -u +%Y-%m-%d)
LOG_FILE="${LOG_DIR}/audit-${TODAY}.log"

# Fast path: skip mkdir/chmod/size-check when today's log already exists.
if [[ ! -f "$LOG_FILE" ]]; then
  mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
  chmod 700 "$LOG_DIR" 2>/dev/null || true
fi

# --- Size guard: rotate if file exceeds 50 MB ---
if [[ -f "$LOG_FILE" ]]; then
  SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if (( SIZE > 52428800 )); then
    N=1
    while [[ -f "${LOG_FILE}.${N}" ]]; do
      N=$((N + 1))
    done
    mv "$LOG_FILE" "${LOG_FILE}.${N}" 2>/dev/null || true
  fi
fi

printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true

exit 0
