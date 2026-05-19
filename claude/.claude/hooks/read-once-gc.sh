#!/usr/bin/env bash
# SessionEnd hook: prune the just-ended session's read-once cache file and
# snapshot directory when its parent transcript is missing or older than
# READ_ONCE_GC_DAYS. Also sweeps orphan snapshot dirs.
#
# Operator opt-out: READ_ONCE_GC_DISABLE=1.
#
# No -e: individual rm/find failures must not abort the GC sweep — the hook
# is best-effort cleanup, not a transaction.
set -uo pipefail

[[ "${READ_ONCE_GC_DISABLE:-0}" == "1" ]] && exit 0

SESSION_ID=""
SESSION_ID="$(jq -r '.session_id // ""' 2>/dev/null)" || true
[[ "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || exit 0

CACHE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude"
GC_DAYS="${READ_ONCE_GC_DAYS:-7}"
CACHE_FILE="$CACHE_DIR/read-cache-$SESSION_ID.jsonl"
SNAP_DIR="$CACHE_DIR/snapshots-$SESSION_ID"

# 1. Drop the just-ended session unless its transcript is still fresh.
transcript_fresh=0
while IFS= read -r tx; do
  if [[ -n "$tx" ]] && \
     find "$tx" -mtime "-$GC_DAYS" -print -quit 2>/dev/null | grep -q .; then
    transcript_fresh=1
    break
  fi
done < <(find "$HOME/.claude/projects" -maxdepth 2 -name "$SESSION_ID.jsonl" 2>/dev/null)

if (( transcript_fresh == 0 )); then
  rm -f -- "$CACHE_FILE"
  rm -rf -- "$SNAP_DIR"
fi

# 2. Orphan snapshot sweep: any snapshots-* dir with no matching cache file.
shopt -s nullglob
for d in "$CACHE_DIR"/snapshots-*; do
  sid="${d##*/snapshots-}"
  [[ -f "$CACHE_DIR/read-cache-$sid.jsonl" ]] || rm -rf -- "$d"
done

exit 0
