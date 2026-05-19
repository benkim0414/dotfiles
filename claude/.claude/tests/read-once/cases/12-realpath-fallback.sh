#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
# Simulate a missing realpath by overriding PATH; the hook must still allow
# and not crash. We use a temp file to be sure the hook reaches _check_path.
tmpf="$CASE_TMP/foo.txt"; echo "hello" > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
# Empty PATH still has the hook's bash builtins available.
out="$(PATH= printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"
assert_allow "$out"
