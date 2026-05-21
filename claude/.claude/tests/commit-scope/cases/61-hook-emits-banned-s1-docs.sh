#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/repo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
stage_file "$dir" "src/auth/login.ts" "x"

out=$(run_hook_in "$dir" 'git commit -m "docs: tweak"')
assert_hook_emits "$out" "scope='docs' is BANNED"
