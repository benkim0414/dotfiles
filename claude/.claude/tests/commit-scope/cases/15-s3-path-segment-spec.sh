#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# 'spec' is singular of 'specs' path segment AND not in history
assert_banned "spec" "docs/superpowers/specs/2026-05-21-foo-design.md"
