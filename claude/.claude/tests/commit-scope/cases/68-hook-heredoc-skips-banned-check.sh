#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
stage_file "$dir" "src/foo.ts" "x"

# Heredoc-style commit: -m argument is a $(cat <<EOF ... EOF) expansion.
# Our regex only matches simple -m "..." or -m '...'; heredoc skipped silently.
out=$(run_hook_in "$dir" 'git commit -m "$(cat <<HEREDOC
docs(spec): something
HEREDOC
)"')
assert_hook_silent_on "$out" "is BANNED"
# But staged context still emitted
assert_hook_emits "$out" "Staged files"
