#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# Multiple top-level dirs -> ambiguous -> empty
assert_suggest_eq "" $'auth/login.ts\napi/handlers.ts'
