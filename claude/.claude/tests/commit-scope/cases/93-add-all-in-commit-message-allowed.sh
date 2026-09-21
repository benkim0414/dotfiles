#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Regression: widening the fast-exit (cases 90-92) made the blanket-staging
# check scan the raw, unstripped command -- so a commit message that quotes
# a banned staging form (documenting the ban, not running it) trips the
# guard. The message content must never be mistaken for the command.
dir="$CASE_TMP/msgquotesaddall"
mkdir -p "$dir"
init_git_fixture "$dir"

status=$(run_hook_in_status "$dir" 'git commit -m "docs: explain why git add -A is banned"')
[[ "$status" == "0" ]] \
  || {
    echo "  hook returned exit=$status; a commit message quoting 'git add -A' must not block" >&2
    exit 1
  }
