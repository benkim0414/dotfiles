#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
stage_file "$dir" "src/auth/login.ts" "x"

# Even when the scope-check emits BANNED, the hook must exit 0 (non-blocking).
# Banned-scope emit is a context warning, not a block.
status=$(run_hook_in_status "$dir" 'git commit -m "feat(docs): tweak"')
[[ "$status" == "0" ]] \
  || { echo "  hook returned exit=$status; expected 0 (non-blocking)" >&2; exit 1; }
