#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

plain="$CASE_TMP/plain/dir"
mkdir -p "$plain"
got=$( cd "$plain" && source "$LIB" && cwd_repo_hint )
assert_eq "" "$got" "cwd_repo_hint outside worktree path"
