#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

bare="$CASE_TMP/bare.git"
mkdir -p "$bare"
(cd "$bare" && git init -q --bare)

status=$(run_arm "$bare" "$(session_start_json)")
[[ "$status" == "0" ]] || {
  echo "  hook exited $status; expected 0" >&2
  exit 1
}
assert_marker_absent
