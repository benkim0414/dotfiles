#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="codex,api"
# OpenSpec-style: openspec/changes/codex-cli-fix/proposal.md
# Deepest non-container dir before file = 'codex-cli-fix' -> match 'codex' (longest suffix)
assert_suggest_eq "codex" "openspec/changes/codex-cli-fix/proposal.md"
