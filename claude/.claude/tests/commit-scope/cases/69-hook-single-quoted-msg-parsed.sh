#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth
stage_file "$dir" "src/foo.ts" "x"

# Single-quoted -m argument: regex captures the inner string.
out=$(run_hook_in "$dir" "git commit -m 'docs(src): tweak'")
assert_hook_emits "$out" "scope='src' is BANNED"
