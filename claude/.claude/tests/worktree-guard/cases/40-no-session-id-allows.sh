#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
set_marker

status=$(run_guard_status "$repo" "$(guard_json_no_sid "$repo/src/a.txt")")
assert_status 0 "$status" "a payload with no session_id must not block"
