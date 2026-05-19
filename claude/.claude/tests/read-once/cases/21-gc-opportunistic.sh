#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
unset READ_ONCE_GC_DISABLE

cache_dir="$CASE_TMP/claude"
mkdir -p "$cache_dir"
old_session="22222222-2222-2222-2222-222222222222"
old_cache="$cache_dir/read-cache-$old_session.jsonl"
echo '{}' > "$old_cache"
# Backdate 8 days
touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null \
            || date -d '8 days ago' +%Y%m%d%H%M)" "$old_cache"

# Trigger the hook with any read; the in-hook prune should fire.
tmpf="$CASE_TMP/foo.txt"; echo hi > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null
# Give the backgrounded prune a moment to run.
sleep 1
[[ ! -e "$old_cache" ]] || { echo "  stale cache should be gone" >&2; exit 1; }
[[ -e "$cache_dir/.last-read-once-prune" ]] \
  || { echo "  prune sentinel missing" >&2; exit 1; }
