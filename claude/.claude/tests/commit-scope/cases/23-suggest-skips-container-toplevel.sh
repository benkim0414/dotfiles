#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# Top-level 'src/' is a container AND file is NOT .md, so step 2 doesn't engage either
# Expected: empty (no useful suggestion derivable without more context)
assert_suggest_eq "" $'src/foo.ts\nsrc/bar.ts'
