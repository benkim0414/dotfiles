#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/myrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
stage_file "$dir" "src/foo.ts" "x"

# Repo basename = 'myrepo' (last segment of $dir). Scope 'myrepo' fires S2.
out=$(run_hook_in "$dir" 'git commit -m "feat(myrepo): tweak"')
assert_hook_emits "$out" "scope='myrepo' is BANNED"
