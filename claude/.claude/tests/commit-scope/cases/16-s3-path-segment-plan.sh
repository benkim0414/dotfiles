#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
assert_banned "plan" "docs/superpowers/plans/2026-05-21-foo.md"
