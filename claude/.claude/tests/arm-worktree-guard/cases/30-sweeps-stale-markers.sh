#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"

# A marker from an abandoned session, older than the 24h cutoff.
stale="$STATE_DIR/pending-99999999-9999-9999-9999-999999999999"
touch "$stale"
touch -t 202001010000 "$stale"

status=$(run_arm "$repo" "$(session_start_json)")
[[ "$status" == "0" ]] || {
  echo "  hook exited $status; expected 0" >&2
  exit 1
}

if [[ -f "$stale" ]]; then
  echo "  stale marker older than 24h was not swept" >&2
  exit 1
fi
assert_marker_present
