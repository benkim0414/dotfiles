#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Regression: the "Allowed git-add — no branch checks needed" early exit
# matched raw $COMMAND, so a `git commit -am` whose MESSAGE merely mentions
# "git add" hit that line and returned 0 before ever reaching the -a guard
# below it -- a real bypass of the atomic-commit enforcement, not a
# hypothetical one.
dir="$CASE_TMP/amwithaddinmsg"
mkdir -p "$dir"
init_git_fixture "$dir"

status=$(run_hook_in_status "$dir" 'git commit -am "docs: prefer git add over -A"')
[[ "$status" == "2" ]] \
  || {
    echo "  hook returned exit=$status; 'git commit -am' must still block even when the message mentions git add" >&2
    exit 1
  }
