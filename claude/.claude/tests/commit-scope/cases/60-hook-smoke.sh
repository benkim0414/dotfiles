#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/repo"
mkdir -p "$dir"
init_git_fixture "$dir"
# Non-git command -> hook should exit cleanly with no JSON
out=$(run_hook_in "$dir" "ls -la")
assert_hook_silent_on "$out" "Scope check"
assert_hook_silent_on "$out" "Staged files"
