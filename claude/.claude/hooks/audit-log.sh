#!/usr/bin/env bash
# audit-log.sh — append a JSONL audit entry for every mutating tool call.
#
# Event:   PostToolUse
# Matcher: Bash|Write|Edit|NotebookEdit|CronCreate|CronDelete|RemoteTrigger|Read|NotebookRead|Grep|mcp__qmd__get|mcp__qmd__multi_get
# Exit:    0 always.
# Async:   yes — must never block Claude Code.
#
# Writes one JSON line per call to ~/.claude/logs/audit-<date>.log, rotating
# at 50 MB. Timestamp + summary are built in a single jq pass (no subprocesses).
set -euo pipefail

# --- Build JSONL entry + today's date in a single jq pass (no subprocesses) ---
IFS=$'\t' read -r ENTRY TODAY <<<"$(cat | jq -r '
  # Generate timestamp and today inside jq (avoids date subprocess).
  (now | strftime("%Y-%m-%dT%H:%M:%SZ")) as $ts |
  (now | strftime("%Y-%m-%d")) as $today |

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
   elif $tool == "Edit" then "edit \($path)"
   elif $tool == "NotebookEdit" then "notebook-edit \($path)"
   elif $tool == "WebFetch"     then "fetch \($url | .[0:200])"
   elif $tool == "WebSearch"    then "search \($query | .[0:200])"
   else "\($tool | ascii_downcase) \($input_keys)" end) as $summary |

  [
    ({
      timestamp: $ts,
      session_id: $sid,
      tool: $tool,
      cwd: $cwd,
      summary: $summary,
      description: $desc,
      output_snippet: $out
    } | tojson),
    $today
  ] | @tsv
')" || true

[[ -z "$ENTRY" ]] && exit 0

# --- Determine log directory and file ---
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/audit-${TODAY}.log"

# Fast path: skip mkdir/chmod/size-check when today's log already exists.
if [[ ! -f "$LOG_FILE" ]]; then
  mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
  chmod 700 "$LOG_DIR" 2>/dev/null || true
fi

# --- Size guard: rotate if file exceeds 50 MB ---
if [[ -f "$LOG_FILE" ]]; then
  SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || stat -f %z "$LOG_FILE" 2>/dev/null || echo 0)
  if ((SIZE > 52428800)); then
    N=1
    while [[ -f "${LOG_FILE}.${N}" ]] && ((N < 100)); do
      N=$((N + 1))
    done
    mv "$LOG_FILE" "${LOG_FILE}.${N}" 2>/dev/null || true
  fi
fi

printf '%s\n' "$ENTRY" >>"$LOG_FILE" 2>/dev/null || true

exit 0
