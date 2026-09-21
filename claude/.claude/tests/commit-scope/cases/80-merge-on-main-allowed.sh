#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# no-pr mode was deleted: merging into main locally is the normal flow here,
# so the hook must not block it regardless of CLAUDE_GIT_WORKFLOW.
dir="$CASE_TMP/mergemain"
mkdir -p "$dir"
init_git_fixture "$dir"
(cd "$dir" && git branch -m main)

unset CLAUDE_GIT_WORKFLOW
status=$(run_hook_in_status "$dir" 'git merge --no-ff topic')
[[ "$status" == "0" ]] \
  || {
    echo "  hook returned exit=$status; merge on main must be allowed" >&2
    exit 1
  }
