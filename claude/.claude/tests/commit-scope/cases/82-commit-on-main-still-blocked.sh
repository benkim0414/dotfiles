#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Commit-on-main was never gated by no-pr mode and must survive its removal.
dir="$CASE_TMP/commitmain"
mkdir -p "$dir"
init_git_fixture "$dir"
(cd "$dir" && git branch -m main)
stage_file "$dir" "src/auth/login.ts" "x"

unset CLAUDE_GIT_WORKFLOW
status=$(run_hook_in_status "$dir" 'git commit -m "feat(auth): add login"')
[[ "$status" == "2" ]] \
  || {
    echo "  hook returned exit=$status; commit on main must still block" >&2
    exit 1
  }
