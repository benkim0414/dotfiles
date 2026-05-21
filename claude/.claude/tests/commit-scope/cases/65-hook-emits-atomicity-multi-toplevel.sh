#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api billing
stage_file "$dir" "auth/login.ts" "x"
stage_file "$dir" "billing/charges.ts" "x"

out=$(run_hook_in "$dir" 'git commit -m "feat(auth): tweak"')
assert_hook_emits "$out" "ATOMICITY"
