#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/data.txt"; echo "line1" > "$tmpf"

# First read (cache miss) -> allow.
payload="$(stdin_for Bash "" 0 -1 "FOO=bar cat $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"; assert_allow "$out"

# Second read with the same prefix -> deny (cache hit).
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"; assert_deny "$out"

# command cat -> also denied (uses same cache entry).
payload2="$(stdin_for Bash "" 0 -1 "command cat $tmpf")"
out="$(printf '%s' "$payload2" | run_hook)"; rc=$?
assert_deny "$out"

# env VAR=val cat -> also denied.
payload3="$(stdin_for Bash "" 0 -1 "env FOO=bar cat $tmpf")"
out="$(printf '%s' "$payload3" | run_hook)"; rc=$?
assert_deny "$out"
