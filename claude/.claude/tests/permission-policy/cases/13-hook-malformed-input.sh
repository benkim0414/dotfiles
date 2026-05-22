#!/usr/bin/env bash
# Hook must never block on malformed/missing input.
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Empty stdin
out=$(printf '' | bash "$HOOK")
[[ -z "$out" ]] || { echo "expected empty out for empty stdin, got '$out'" >&2; exit 1; }

# Non-JSON stdin
out=$(printf 'not json' | bash "$HOOK")
[[ -z "$out" ]] || { echo "expected empty out for non-json, got '$out'" >&2; exit 1; }

# JSON without tool_name
envelope=$(jq -cn '{tool_input:{command:"ls"}}')
assert_hook_silent "$envelope"

# Unknown tool name
envelope=$(jq -cn '{tool_name:"SomeNewTool", tool_input:{x:"y"}}')
assert_hook_silent "$envelope"
