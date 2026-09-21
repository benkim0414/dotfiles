#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
set_marker

outside="$CASE_TMP/scratch/note.md"
status=$(run_guard_status "$repo" "$(guard_json "$outside")")
assert_status 0 "$status" "path outside the working tree must be allowed"
