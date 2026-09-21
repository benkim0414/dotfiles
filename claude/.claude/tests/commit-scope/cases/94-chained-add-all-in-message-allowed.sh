#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Same as case 93, chained after a cd -- proves the fix did not simply
# re-open the bypass cases 90-92 close.
dir="$CASE_TMP/chainedmsgquotesaddall"
mkdir -p "$dir"
init_git_fixture "$dir"

status=$(run_hook_in_status "$dir" 'cd /tmp && git commit -m "docs: git add -A is banned"')
[[ "$status" == "0" ]] \
  || {
    echo "  hook returned exit=$status; a chained commit message quoting 'git add -A' must not block" >&2
    exit 1
  }
