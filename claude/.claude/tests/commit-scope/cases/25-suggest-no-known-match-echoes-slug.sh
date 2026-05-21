#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# Date slug 'unknown-thing' has no known-scope match -> echo bare candidate
assert_suggest_eq "unknown-thing" "docs/superpowers/specs/2026-05-21-unknown-thing-design.md"
