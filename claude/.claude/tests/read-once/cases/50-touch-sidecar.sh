#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"

payload="$(stdin_for Bash "" 0 -1 "touch $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"
# Cold touch -> allow (no cached read on this path yet).
assert_allow "$out"

sidecar="$CASE_TMP/claude/touch-events-$SESSION_ID.jsonl"
[[ -f "$sidecar" ]] || { echo "  touch sidecar missing" >&2; exit 1; }
grep -q "$tmpf" "$sidecar" || { echo "  path not recorded in sidecar" >&2; exit 1; }
