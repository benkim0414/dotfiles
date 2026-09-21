#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Pushing main after a local merge is the normal flow. The permissions.ask
# rules still prompt for it; the hook must not hard-block it.
dir="$CASE_TMP/pushmain"
mkdir -p "$dir"
init_git_fixture "$dir"
(cd "$dir" && git branch -m main)

unset CLAUDE_GIT_WORKFLOW
status=$(run_hook_in_status "$dir" 'git push origin main')
[[ "$status" == "0" ]] \
  || {
    echo "  hook returned exit=$status; push to main must be allowed" >&2
    exit 1
  }
