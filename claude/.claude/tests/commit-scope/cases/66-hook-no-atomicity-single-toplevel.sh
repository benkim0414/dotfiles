#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
stage_file "$dir" "auth/login.ts" "x"
stage_file "$dir" "auth/logout.ts" "x"

out=$(run_hook_in "$dir" 'git commit -m "feat(auth): tweak"')
assert_hook_silent_on "$out" "ATOMICITY"
