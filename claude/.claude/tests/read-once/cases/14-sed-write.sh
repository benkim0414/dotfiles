#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/data.txt"; echo "old" > "$tmpf"

# Pre-seed cache by reading the file via Read.
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null

# Now sed -i to edit it. This is a WRITE; must NOT be denied.
payload="$(stdin_for Bash "" 0 -1 "sed -i 's/old/new/' $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"; assert_allow "$out"

# BSD form: sed -i '' '...' file
payload="$(stdin_for Bash "" 0 -1 "sed -i '' 's/old/new/' $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_allow "$out"

# Suffix form: sed -i.bak '...' file
payload="$(stdin_for Bash "" 0 -1 "sed -i.bak 's/old/new/' $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_allow "$out"

# Stdin sed (no positional file): always allow.
payload="$(stdin_for Bash "" 0 -1 "sed 's/x/y/'")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_allow "$out"

# Real read: sed 's/x/y/' file -> first call allow, second call deny (cache hit).
payload="$(stdin_for Bash "" 0 -1 "sed 's/old/new/' $tmpf")"
printf '%s' "$payload" | run_hook >/dev/null
out="$(printf '%s' "$payload" | run_hook)"
assert_deny "$out"
