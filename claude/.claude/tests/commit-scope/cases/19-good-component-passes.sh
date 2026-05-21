#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# 'auth' is in history, not a container, not repo name, not a stale path segment
assert_not_banned "auth" $'src/auth/login.ts\ntests/auth/login_test.ts'
