#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
export READ_ONCE_DIFF=1
tmpf="$CASE_TMP/f.txt"
printf 'a\nb\nc\nd\ne\n' > "$tmpf"
# First read is partial (offset=1, limit=2).
payload="$(stdin_for Read "$tmpf" 1 2)"
printf '%s' "$payload" | run_hook >/dev/null
# Snapshot must exist despite the partial first read.
snap_dir="$CASE_TMP/claude/snapshots-$SESSION_ID"
[[ -d "$snap_dir" && -n "$(ls -A "$snap_dir")" ]] \
  || { echo "  snapshot not stored on partial first read" >&2; exit 1; }
