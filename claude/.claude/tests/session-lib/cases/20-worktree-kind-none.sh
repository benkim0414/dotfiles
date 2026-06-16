#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

mkdir -p "$CASE_TMP/nogit"
got=$( cd "$CASE_TMP/nogit" && source "$LIB" && worktree_kind )
assert_eq "none" "$got" "worktree_kind outside a git repo"
