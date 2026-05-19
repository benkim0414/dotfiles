#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
export READ_ONCE_DIFF=1
# Read 55 distinct files; snapshot dir should never exceed 50 entries.
for i in $(seq 1 55); do
  f="$CASE_TMP/f-$i.txt"
  echo "$i" > "$f"
  payload="$(stdin_for Read "$f")"
  printf '%s' "$payload" | run_hook >/dev/null
done
snap_dir="$CASE_TMP/claude/snapshots-$SESSION_ID"
n=$(ls "$snap_dir" 2>/dev/null | wc -l | tr -d ' ')
(( n <= 50 )) || { echo "  snapshot dir has $n entries (>50)" >&2; exit 1; }
