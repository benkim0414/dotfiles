#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
# helpers.sh sets READ_ONCE_DIFF=0 explicitly; clear it to test the default.
unset READ_ONCE_DIFF
tmpf="$CASE_TMP/f.txt"
printf 'a\nb\nc\n' > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null

# Small edit; diff mode should produce a diff-flavoured deny.
sleep 2
echo "d" >> "$tmpf"
out="$(printf '%s' "$payload" | run_hook)"
assert_deny "$out"
assert_deny_contains "$out" "Diff"

# Reason should mention ~tokens.
echo "$out" | jq -re '.hookSpecificOutput.permissionDecisionReason' \
  | grep -qE '~[0-9]+ tokens' \
  || { echo "  diff reason missing token estimate" >&2; exit 1; }
