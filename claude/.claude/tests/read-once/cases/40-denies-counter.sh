#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null    # cache miss
printf '%s' "$payload" | run_hook >/dev/null    # 1st deny
printf '%s' "$payload" | run_hook >/dev/null    # 2nd deny

cache="$CASE_TMP/claude/read-cache-$SESSION_ID.jsonl"
last_denies=$(jq -r 'select(.path|test("f.txt$"))|.denies // 0' "$cache" | tail -1)
(( last_denies == 2 )) || { echo "  expected denies=2, got $last_denies" >&2; exit 1; }
