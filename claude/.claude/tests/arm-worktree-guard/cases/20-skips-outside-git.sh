#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

plain="$CASE_TMP/notarepo"
mkdir -p "$plain"

status=$(run_arm "$plain" "$(session_start_json)")
[[ "$status" == "0" ]] || {
  echo "  hook exited $status; expected 0" >&2
  exit 1
}
assert_marker_absent
