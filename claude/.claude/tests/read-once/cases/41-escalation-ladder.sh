#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null   # miss

# Deny #1 -> rank 0 wording (no "STILL", no "DENY #").
out="$(printf '%s' "$payload" | run_hook)"
assert_deny_contains "$out" "in context"
echo "$out" | jq -re '.hookSpecificOutput.permissionDecisionReason' \
  | grep -qE 'STILL|DENY #' \
  && { echo "  rank 0 should not contain escalation keywords" >&2; exit 1; }

# Deny #2 (rank 1) -> contains "STILL".
out="$(printf '%s' "$payload" | run_hook)"
assert_deny_contains "$out" "STILL"

# Denies 3, 4 (rank 1 still through 3-5 band).
printf '%s' "$payload" | run_hook >/dev/null
out="$(printf '%s' "$payload" | run_hook)"   # deny #4 -> rank 3 (3-5 band)
assert_deny_contains "$out" "DENY #"

# Push to rank 6+.
for _ in 5 6 7; do printf '%s' "$payload" | run_hook >/dev/null; done
out="$(printf '%s' "$payload" | run_hook)"
assert_deny_contains "$out" "READ_ONCE_DISABLE=1"
