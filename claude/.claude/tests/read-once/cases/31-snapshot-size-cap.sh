#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
export READ_ONCE_DIFF=1
export READ_ONCE_DIFF_MAX_BYTES=64
tmpf="$CASE_TMP/big.txt"
head -c 1024 /dev/urandom | base64 > "$tmpf"   # > 1KB > 64
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null
snap_dir="$CASE_TMP/claude/snapshots-$SESSION_ID"
# Snapshot should NOT exist for an oversize file.
if [[ -d "$snap_dir" ]] && [[ -n "$(ls -A "$snap_dir" 2>/dev/null)" ]]; then
  echo "  oversize file was snapshotted" >&2; exit 1
fi
