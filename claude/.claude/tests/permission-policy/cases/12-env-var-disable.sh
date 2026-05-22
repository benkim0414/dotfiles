#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Sanity: hook surfaces ask for a known-bad Bash command.
bad=$(pretooluse_json Bash command 'cat /Users/ben/.ssh/id_rsa')
assert_hook_asks "$bad" 'secret path'

# Sanity: hook is silent for a benign command.
benign=$(pretooluse_json Bash command 'ls /tmp')
assert_hook_silent "$benign"

# CLAUDE_PERMISSION_POLICY=off short-circuits.
export CLAUDE_PERMISSION_POLICY=off
also_bad=$(pretooluse_json Bash command 'cat /Users/ben/.ssh/id_rsa')
assert_hook_silent "$also_bad"
unset CLAUDE_PERMISSION_POLICY
