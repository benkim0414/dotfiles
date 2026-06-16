#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

got=$( source "$LIB"; unset CLAUDE_GIT_WORKFLOW; if workflow_no_pr; then echo yes; else echo no; fi )
assert_eq "no" "$got" "workflow_no_pr when unset"

got2=$( source "$LIB"; CLAUDE_GIT_WORKFLOW=pr; if workflow_no_pr; then echo yes; else echo no; fi )
assert_eq "no" "$got2" "workflow_no_pr when env=other value"
