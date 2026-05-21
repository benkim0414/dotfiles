#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Bootstrap friction (documented in spec):
# First commit of a brand-new component in a fresh repo will be flagged BANNED
# via S3 because the new scope matches the new directory name AND is not yet in
# `git log` history. Acceptable -- the warning settles once the scope lands in
# history. This test LOCKS the documented behavior so future changes that try
# to "fix" S3 to silently allow first commits are surfaced as breaking.

dir="$CASE_TMP/freshrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
# No seed_known_scopes -> only 'seed' in history.
stage_file "$dir" "billing/charges.ts" "x"

out=$(run_hook_in "$dir" 'git commit -m "feat(billing): initial billing"')
# S3 fires on 'billing' path segment, not yet in history.
assert_hook_emits "$out" "scope='billing' is BANNED"

# But the hook still exits cleanly (non-blocking).
status=$(run_hook_in_status "$dir" 'git commit -m "feat(billing): initial billing"')
[[ "$status" == "0" ]] \
  || { echo "  hook returned exit=$status during bootstrap; expected 0" >&2; exit 1; }
