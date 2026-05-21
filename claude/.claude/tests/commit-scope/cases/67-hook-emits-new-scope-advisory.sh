#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
# Staged file is under top-level 'auth/' so suggest_scope returns 'auth' (in history).
# Agent declares 'billing' instead -- not in history AND not derived from paths.
stage_file "$dir" "auth/login.ts" "x"

out=$(run_hook_in "$dir" 'git commit -m "feat(billing): tweak auth"')
assert_hook_silent_on "$out" "is BANNED"
assert_hook_emits "$out" "NEW SCOPE"
