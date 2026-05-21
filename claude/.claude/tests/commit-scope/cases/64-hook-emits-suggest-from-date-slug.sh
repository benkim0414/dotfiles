#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" read-once auth
stage_file "$dir" "docs/superpowers/specs/2026-05-21-read-once-foo-design.md" "x"

out=$(run_hook_in "$dir" 'git commit -m "docs(read-once): add spec"')
assert_hook_emits "$out" "Suggested scope (derived): read-once"
