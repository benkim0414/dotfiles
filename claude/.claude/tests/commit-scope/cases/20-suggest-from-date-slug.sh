#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="read-once,auth,api"
# Date-slug 'read-once-hardening' matches known scope 'read-once' (longest suffix match)
assert_suggest_eq "read-once" "docs/superpowers/specs/2026-05-21-read-once-hardening-design.md"
