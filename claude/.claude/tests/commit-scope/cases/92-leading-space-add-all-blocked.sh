#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Regression: a single leading space before "git" also defeated the `"git `
# anchor (the JSON quote is no longer immediately followed by "git ").
dir="$CASE_TMP/leadingspace"
mkdir -p "$dir"
init_git_fixture "$dir"

status=$(run_hook_in_status "$dir" ' git add -A')
[[ "$status" == "2" ]] \
  || {
    echo "  hook returned exit=$status; leading-space 'git add -A' must block" >&2
    exit 1
  }
