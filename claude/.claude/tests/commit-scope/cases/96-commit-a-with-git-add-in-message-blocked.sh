#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Same bypass as case 95, with -a and -m as separate flags rather than -am.
dir="$CASE_TMP/awithaddinmsg"
mkdir -p "$dir"
init_git_fixture "$dir"

status=$(run_hook_in_status "$dir" 'git commit -a -m "docs: use git add <path>"')
[[ "$status" == "2" ]] \
  || {
    echo "  hook returned exit=$status; 'git commit -a' must still block even when the message mentions git add" >&2
    exit 1
  }
