#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
clear_marker

status=$(run_guard_status "$repo" "$(guard_json "$repo/src/a.txt")")
assert_status 0 "$status" "no marker must allow"
