#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
stage_file "$dir" "openspec/changes/codex-cli-fix/proposal.md" "x"

# 'openspec' is a path segment, NOT in known scopes -> S3 fires
out=$(run_hook_in "$dir" 'git commit -m "docs(openspec): add proposal"')
assert_hook_emits "$out" "scope='openspec' is BANNED"
