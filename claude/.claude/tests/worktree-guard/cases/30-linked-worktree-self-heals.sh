#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
wt="$(add_linked_worktree "$repo" feat)"
set_marker

status=$(run_guard_status "$wt" "$(guard_json "$wt/src/a.txt")")
assert_status 0 "$status" "edits inside a linked worktree must be allowed"

if marker_exists; then
  echo "  stale marker was not cleared by the self-healing branch" >&2
  exit 1
fi
