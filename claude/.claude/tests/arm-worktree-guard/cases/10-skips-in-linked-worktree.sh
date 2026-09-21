#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
wt="$(add_linked_worktree "$repo" feat)"

status=$(run_arm "$wt" "$(session_start_json)")
[[ "$status" == "0" ]] || {
  echo "  hook exited $status; expected 0" >&2
  exit 1
}
assert_marker_absent
