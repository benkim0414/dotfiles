#!/usr/bin/env bash
# Codex PostToolUse hook: append lightweight JSONL audit entries.
set -euo pipefail

input=$(cat)
IFS=$'\t' read -r entry today < <(
  printf '%s' "$input" | jq -r '
    (now | strftime("%Y-%m-%dT%H:%M:%SZ")) as $ts |
    (now | strftime("%Y-%m-%d")) as $today |
    (.tool_name // "") as $tool |
    (.session_id // "") as $sid |
    (.cwd // "") as $cwd |
    ((.tool_input.command // .tool_input.cmd // "") | gsub("\n"; "\\n") | .[0:500]) as $cmd |
    ((.tool_input // {}) | keys_unsorted | join(",")) as $keys |
    ((.tool_response // .tool_output // "") | tostring | .[0:200]) as $out |
    (if $tool == "Bash" then $cmd
     elif $tool == "apply_patch" then "apply_patch"
     else "\($tool) \($keys)" end) as $summary |
    [({
      timestamp: $ts,
      session_id: $sid,
      tool: $tool,
      cwd: $cwd,
      summary: $summary,
      output_snippet: $out
    } | tojson), $today] | @tsv
  ' 2>/dev/null
) || true

[[ -n "${entry:-}" && -n "${today:-}" ]] || exit 0

log_dir="${HOME}/.codex/logs"
log_file="${log_dir}/audit-${today}.log"
mkdir -p "$log_dir" 2>/dev/null || exit 0
chmod 700 "$log_dir" 2>/dev/null || true

if [[ -f "$log_file" ]]; then
  size=$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file" 2>/dev/null || echo 0)
  if (( size > 52428800 )); then
    n=1
    while [[ -f "${log_file}.${n}" ]] && (( n < 100 )); do
      n=$((n + 1))
    done
    mv "$log_file" "${log_file}.${n}" 2>/dev/null || true
  fi
fi

printf '%s\n' "$entry" >> "$log_file" 2>/dev/null || true
