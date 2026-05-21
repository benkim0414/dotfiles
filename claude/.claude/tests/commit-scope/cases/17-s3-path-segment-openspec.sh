#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
assert_banned "openspec" "openspec/changes/foo/proposal.md"
