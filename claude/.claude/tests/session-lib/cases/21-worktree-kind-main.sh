#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/mainrepo"
mkdir -p "$repo"
init_main_repo "$repo"
got=$( cd "$repo" && source "$LIB" && worktree_kind )
assert_eq "main" "$got" "worktree_kind in primary working tree"
