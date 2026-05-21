#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
stage_file "$dir" "src/foo.ts" "x"

# No -m at all (editor-based commit). declared_scope stays empty -> banned-check skipped.
out=$(run_hook_in "$dir" 'git commit')
assert_hook_silent_on "$out" "is BANNED"
# Staged context still emitted
assert_hook_emits "$out" "Staged files"
