#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Regression: same fast-exit bypass as case 90, for `git commit -am` chained
# after a `cd`. `cd <dir> && git commit -am "..."` is the most common shape
# Claude Code emits, so this was the practical failure mode, not an edge case.
dir="$CASE_TMP/chainedcommit"
mkdir -p "$dir"
init_git_fixture "$dir"

status=$(run_hook_in_status "$dir" 'cd /tmp && git commit -am "chore: x"')
[[ "$status" == "2" ]] \
  || {
    echo "  hook returned exit=$status; chained 'cd && git commit -am' must block" >&2
    exit 1
  }
