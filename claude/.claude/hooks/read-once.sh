#!/usr/bin/env bash
# PreToolUse hook (matchers: Read, NotebookRead, mcp__qmd__get):
# Block redundant reads when the same file+range is already in this session's
# context. Based on the community "read-once" pattern (Boucle, egorfedorov).
#
# Cache (JSONL, append-only, last matching line wins per path):
#   ${XDG_RUNTIME_DIR:-$HOME/.cache}/claude/read-cache-<SESSION_ID>.jsonl
#   {"path":"/abs","mtime":1713200000,"ranges":[[0,-1]],"ts":1713203600}
#
# Escape hatches (any true → allow + record fresh entry):
#   - mtime changed on disk (external edit invalidated the cached view)
#   - requested (offset,limit) not covered by any prior range
#   - now - ts >= READ_ONCE_TTL (default 1200s; guards context compaction;
#     TTL=0 disables caching)
#   - READ_ONCE_DISABLE=1 set in the environment
#   - no session_id / file missing / stat failure / corrupt cache
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

# Tab-separated so paths with spaces survive `read`.
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
[[ "$CURRENT_MTIME" =~ ^[0-9]+$ && "$CURRENT_MTIME" -gt 0 ]] || exit 0

TTL="${READ_ONCE_TTL:-1200}"
NOW="${EPOCHSECONDS:-$(date +%s)}"

CACHE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude"
mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0
CACHE="${CACHE_DIR}/read-cache-${SESSION_ID}.jsonl"

record() {
  local ranges="$1"
  jq -cn \
    --arg path "$ABS" \
    --argjson mtime "$CURRENT_MTIME" \
    --argjson ranges "$ranges" \
    --argjson ts "$NOW" \
    '{path:$path, mtime:$mtime, ranges:$ranges, ts:$ts}' \
    >> "$CACHE" 2>/dev/null || true
}

# Single jq pass over the cache: find the last entry for this path, compute
# coverage of the requested (offset,limit), and emit the ranges-extended-with-
# new-request as a JSON array. Tab-sep output: STATUS<TAB>mtime<TAB>ts<TAB>covered<TAB>extended.
# STATUS=NEW when no prior entry exists; HIT otherwise.
STATUS=NEW P_MTIME=0 P_TS=0 COVERED=false EXTENDED="[[${OFFSET}, ${LIMIT}]]"
if [[ -f "$CACHE" ]]; then
  IFS=$'\t' read -r STATUS P_MTIME P_TS COVERED EXTENDED < <(
    jq -rs --arg p "$ABS" --argjson o2 "$OFFSET" --argjson l2 "$LIMIT" '
      [.[] | select(.path == $p)] | last as $prior |
      if $prior == null then "NEW\t0\t0\tfalse\t[]"
      else
        ([$prior.ranges[]? |
          .[0] as $o1 | .[1] as $l1 |
          if $o1 <= $o2 then
            if $l2 == -1 then ($l1 == -1)
            elif $l1 == -1 then true
            else ($o1 + $l1) >= ($o2 + $l2)
            end
          else false end
        ] | any) as $cov |
        "HIT\t\($prior.mtime)\t\($prior.ts)\t\($cov)\t\($prior.ranges + [[$o2, $l2]] | tojson)"
      end
    ' "$CACHE" 2>/dev/null
  ) || true
fi

if [[ "$STATUS" != "HIT" ]]; then
  record "[[${OFFSET}, ${LIMIT}]]"
  exit 0
fi

if [[ "$P_MTIME" != "$CURRENT_MTIME" ]]; then
  record "[[${OFFSET}, ${LIMIT}]]"
  exit 0
fi

if (( NOW - P_TS >= TTL )); then
  record "[[${OFFSET}, ${LIMIT}]]"
  exit 0
fi

if [[ "$COVERED" != "true" ]]; then
  record "$EXTENDED"
  exit 0
fi

# Block. Size stat is deferred here because it's only used for the token estimate.
SIZE=$(stat -c %s "$ABS" 2>/dev/null || stat -f %z "$ABS" 2>/dev/null || echo 0)
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
