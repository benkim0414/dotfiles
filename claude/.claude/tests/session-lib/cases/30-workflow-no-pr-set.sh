#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

got=$( source "$LIB"; CLAUDE_GIT_WORKFLOW=no-pr; if workflow_no_pr; then echo yes; else echo no; fi )
assert_eq "yes" "$got" "workflow_no_pr when env=no-pr"
