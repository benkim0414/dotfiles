#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# Single top-level non-container 'auth/' -> candidate 'auth' -> known scope match
assert_suggest_eq "auth" $'auth/login.ts\nauth/logout.ts'
