#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

fake="$CASE_TMP/myrepo/.claude/worktrees/wt1/sub"
mkdir -p "$fake"
got=$( cd "$fake" && source "$LIB" && cwd_repo_hint )
want=$( cd "$fake" && printf '%s' "${PWD%%/.claude/worktrees/*}" )
assert_eq "$want" "$got" "cwd_repo_hint under worktree"
