#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# THE decisive case. If this passes against a deleted or neutered guard,
# the whole suite is worthless. See step 5 of Task 1.
repo="$CASE_TMP/repo"
make_repo "$repo"
set_marker

status=$(run_guard_status "$repo" "$(guard_json "$repo/src/a.txt")")
assert_status 2 "$status" "marker + in-repo path must block"
