#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
stage_file "$dir" "docs/policy.md" "x"

# Unscoped commit (`docs: tweak policy`) is valid per CLAUDE.md.
# Hook must NOT emit a BANNED warning for it.
out=$(run_hook_in "$dir" 'git commit -m "docs: tweak repo-wide policy"')
assert_hook_silent_on "$out" "is BANNED"
