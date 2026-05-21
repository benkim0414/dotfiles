#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
# 'docs' is a container BUT also a real scope in this repo's history -> not banned
export COMMIT_SCOPE_KNOWN_OVERRIDE="docs,api,auth"
assert_not_banned "docs"
