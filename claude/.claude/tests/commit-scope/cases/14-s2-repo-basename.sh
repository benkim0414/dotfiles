#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="myapp"
export COMMIT_SCOPE_KNOWN_OVERRIDE="myapp,api"  # even if in history, S2 has no escape
assert_banned "myapp"
