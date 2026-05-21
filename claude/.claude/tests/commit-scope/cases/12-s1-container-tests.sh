#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE=""
assert_banned "tests"
