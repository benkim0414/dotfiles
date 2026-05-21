#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
# 'auth' is a path segment of src/auth/login.ts AND already in history -> allowed
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
assert_not_banned "auth" $'src/auth/login.ts'
