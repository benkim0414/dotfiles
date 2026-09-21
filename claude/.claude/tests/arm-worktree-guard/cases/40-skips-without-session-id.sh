#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"

# parse_session_id yields empty for a non-UUID. The marker is keyed by
# session id, so the hook must exit 0 and arm nothing at all.
json=$(jq -cn '{session_id:"not-a-uuid", hook_event_name:"SessionStart"}')
status=$(run_arm "$repo" "$json")
[[ "$status" == "0" ]] || {
  echo "  hook exited $status; expected 0" >&2
  exit 1
}

if find "$STATE_DIR" -name 'pending-*' | grep -q .; then
  echo "  hook armed a marker despite having no usable session id" >&2
  exit 1
fi
