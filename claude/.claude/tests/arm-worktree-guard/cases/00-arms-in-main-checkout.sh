#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"

status=$(run_arm "$repo" "$(session_start_json)")
[[ "$status" == "0" ]] || {
  echo "  hook exited $status; SessionStart must not block" >&2
  exit 1
}
assert_marker_present
