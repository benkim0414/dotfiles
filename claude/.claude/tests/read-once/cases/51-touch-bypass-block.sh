#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"

# Read first to seed the cache.
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null

# Immediate touch on the same path -> DENY.
t_payload="$(stdin_for Bash "" 0 -1 "touch $tmpf")"
out="$(printf '%s' "$t_payload" | run_hook)"
assert_deny "$out"
assert_deny_contains "$out" "touch on recently-read file"
