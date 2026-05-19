#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
GC_HOOK="$(dirname "${BASH_SOURCE[0]}")/../../../hooks/read-once-gc.sh"
[[ -x "$GC_HOOK" ]] || { echo "  GC hook missing/not exec: $GC_HOOK" >&2; exit 1; }

unset READ_ONCE_GC_DISABLE
cache_dir="$CASE_TMP/claude"
cache_file="$cache_dir/read-cache-$SESSION_ID.jsonl"
snap_dir="$cache_dir/snapshots-$SESSION_ID"
mkdir -p "$snap_dir"
echo '{"path":"/x","mtime":0,"ranges":[[0,-1]],"ts":0,"denies":0}' > "$cache_file"
touch "$snap_dir/dummy"

payload="$(jq -cn --arg sid "$SESSION_ID" '{session_id:$sid}')"
printf '%s' "$payload" | bash "$GC_HOOK"

[[ ! -e "$cache_file" ]] || { echo "  cache file should be gone" >&2; exit 1; }
[[ ! -e "$snap_dir"  ]] || { echo "  snap dir should be gone" >&2; exit 1; }
