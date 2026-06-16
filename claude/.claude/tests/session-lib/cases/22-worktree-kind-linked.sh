#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/lrepo"
mkdir -p "$repo"
init_main_repo "$repo"
wt="$CASE_TMP/lrepo-wt"
add_linked_worktree "$repo" "$wt"
got=$( cd "$wt" && source "$LIB" && worktree_kind )
assert_eq "linked" "$got" "worktree_kind in a linked worktree"
