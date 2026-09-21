#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Regression: the old fast-exit tested for the literal `"git ` (a JSON quote
# immediately followed by "git "), which only matches when the payload's
# command STARTS with git. `cd <dir> && git add -A` never starts with git,
# so it skipped every guard below and the blanket-staging block never fired.
dir="$CASE_TMP/chainedadd"
mkdir -p "$dir"
init_git_fixture "$dir"

status=$(run_hook_in_status "$dir" 'cd /tmp && git add -A')
[[ "$status" == "2" ]] \
  || {
    echo "  hook returned exit=$status; chained 'cd && git add -A' must block" >&2
    exit 1
  }
