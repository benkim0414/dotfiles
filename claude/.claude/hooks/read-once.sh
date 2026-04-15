#!/usr/bin/env bash
# PreToolUse hook (matchers: Read, NotebookRead, mcp__qmd__get):
# Block redundant reads when the same file+range is already in this session's
# context. Based on the community "read-once" pattern (Boucle, egorfedorov).
#
# Cache (JSONL, append-only, last line wins per path):
#   ~/.cache/claude/read-cache-<SESSION_ID>.jsonl
#   {"path":"/abs","mtime":1713200000,"ranges":[[0,-1]],"ts":1713203600,"size":12345}
#
# Escape hatches (any true → allow + record fresh entry):
#   - mtime changed on disk (external edit invalidated the cached view)
#   - requested (offset,limit) not covered by any prior range
#   - now - ts > READ_ONCE_TTL (default 1200s, guards context compaction)
#   - READ_ONCE_DISABLE=1 set in the environment
#   - no session_id / file missing / non-numeric mtime / corrupt cache
#
# Silent exit 0 = allow. JSON permissionDecision="deny" = block the tool call.
# Range semantics match Claude Code's Read tool: offset/limit are line counts;
# limit == -1 means "whole file from offset".
set -euo pipefail

[[ "${READ_ONCE_DISABLE:-0}" == "1" ]] && exit 0

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)
SESSION_ID=$(parse_session_id "$INPUT")
[[ -n "$SESSION_ID" ]] || exit 0

# Extract path + optional offset/limit. Tab-separated so paths with spaces survive.
FILE_PATH="" OFFSET=0 LIMIT=-1
IFS=$'\t' read -r FILE_PATH OFFSET LIMIT < <(
  printf '%s' "$INPUT" | jq -r '
    [
      (.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""),
      (.tool_input.offset // 0),
      (.tool_input.limit // -1)
    ] | @tsv
  ' 2>/dev/null
) || true

[[ -n "$FILE_PATH" ]] || exit 0

# qmd can receive a docid like "#abc123" — not a real path; skip caching.
[[ "$FILE_PATH" == \#* ]] && exit 0

# Resolve symlinks (stow-managed dotfiles → their source in the repo).
ABS=$(realpath -m "$FILE_PATH" 2>/dev/null || grealpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# If the path doesn't exist, let the tool surface its own error.
[[ -e "$ABS" ]] || exit 0

CURRENT_MTIME=$(file_mtime "$ABS")
[[ "$CURRENT_MTIME" =~ ^[0-9]+$ ]] && [[ "$CURRENT_MTIME" -gt 0 ]] || exit 0

SIZE=$(stat -c %s "$ABS" 2>/dev/null || stat -f %z "$ABS" 2>/dev/null || echo 0)
TTL="${READ_ONCE_TTL:-1200}"
NOW="${EPOCHSECONDS:-$(date +%s)}"

CACHE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache/claude}"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
CACHE="${CACHE_DIR}/read-cache-${SESSION_ID}.jsonl"

# Append one entry for (path, mtime, ranges). `ranges` arg is a JSON array string.
record() {
  local ranges="$1"
  jq -cn \
    --arg path "$ABS" \
    --argjson mtime "$CURRENT_MTIME" \
    --argjson ranges "$ranges" \
    --argjson ts "$NOW" \
    --argjson size "$SIZE" \
    '{path:$path, mtime:$mtime, ranges:$ranges, ts:$ts, size:$size}' \
    >> "$CACHE" 2>/dev/null || true
}

# Most recent entry for this path (last matching line in JSONL).
PRIOR=""
if [[ -f "$CACHE" ]]; then
  PRIOR=$(jq -c --arg p "$ABS" 'select(.path == $p)' "$CACHE" 2>/dev/null | tail -n 1 || true)
fi

# First read → record and allow.
if [[ -z "$PRIOR" ]]; then
  record "[[${OFFSET}, ${LIMIT}]]"
  exit 0
fi

P_MTIME=$(printf '%s' "$PRIOR" | jq -r '.mtime // 0' 2>/dev/null || echo 0)
P_TS=$(printf '%s' "$PRIOR" | jq -r '.ts // 0' 2>/dev/null || echo 0)

# File changed on disk → invalidate and allow.
if [[ "$P_MTIME" != "$CURRENT_MTIME" ]]; then
  record "[[${OFFSET}, ${LIMIT}]]"
  exit 0
fi

# TTL elapsed → Claude Code may have compacted; allow to avoid starving context.
# Uses >= so READ_ONCE_TTL=0 is a functional "always expire" knob.
if (( NOW - P_TS >= TTL )); then
  record "[[${OFFSET}, ${LIMIT}]]"
  exit 0
fi

# Range coverage check.
# Prior (o1,l1) covers new (o2,l2) iff o1 <= o2 AND:
#   - l2 == -1 (new is "to end")  →  l1 == -1
#   - l1 == -1 (prior is "to end") →  always true (for any finite l2)
#   - both finite                  →  o1+l1 >= o2+l2
COVERED=$(printf '%s' "$PRIOR" | jq --argjson o2 "$OFFSET" --argjson l2 "$LIMIT" '
  [.ranges[]? |
    .[0] as $o1 | .[1] as $l1 |
    if $o1 <= $o2 then
      if $l2 == -1 then ($l1 == -1)
      elif $l1 == -1 then true
      else ($o1 + $l1) >= ($o2 + $l2)
      end
    else false end
  ] | any' 2>/dev/null || echo false)

if [[ "$COVERED" != "true" ]]; then
  # New range; extend coverage on the same (path, mtime) entry.
  EXTENDED=$(printf '%s' "$PRIOR" | jq -c --argjson o2 "$OFFSET" --argjson l2 "$LIMIT" \
    '.ranges + [[$o2, $l2]]' 2>/dev/null || echo "[[${OFFSET}, ${LIMIT}]]")
  record "$EXTENDED"
  exit 0
fi

# All escape hatches failed → block with an actionable reason.
AGE=$(( NOW - P_TS ))
TOKENS=$(( SIZE / 4 ))
REASON="read-once: ${ABS} already in context (read ${AGE}s ago, unchanged, ~${TOKENS} tokens). Edit the file, request a different offset/limit, wait ${TTL}s for TTL, or set READ_ONCE_DISABLE=1 to bypass."

jq -cn --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
