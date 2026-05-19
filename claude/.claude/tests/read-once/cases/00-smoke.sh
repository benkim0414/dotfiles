#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
# A read on a non-existent file should pass through (stat fails → allow).
payload="$(stdin_for Read /no/such/path)"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"
assert_allow "$out"
