#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
export READ_ONCE_DIFF=1
export READ_ONCE_DIFF_MAX=4
tmpf="$CASE_TMP/f.txt"
printf 'a\nb\nc\n' > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null   # cache + snapshot

# Ensure subsequent write lands in a different mtime second.
sleep 2
# Replace contents entirely (big diff >4 lines).
printf 'X\nY\nZ\nW\nV\nU\n' > "$tmpf"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
# Big diff -> fallback to allow.
assert_exit 0 "$rc"; assert_allow "$out"
