#!/usr/bin/env bash
# Lib-level: bypass attempts that evade the `Bash(rm -rf *)` ask pattern.
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Positive: must flag
assert_bash_flagged '\rm -rf /tmp/x'
assert_bash_flagged 'command rm -rf /tmp/x'
assert_bash_flagged 'builtin rm -rf /tmp/x'
assert_bash_flagged '  rm -rf /tmp/x'
assert_bash_flagged '"rm" -rf /tmp/x'
assert_bash_flagged "'rm' -rf /tmp/x"

# Negative: plain `rm somefile` (no -rf) is silent; `rm -rf` itself is caught by
# the existing settings ask entry, not this lib check.
assert_bash_silent 'rm somefile'
assert_bash_silent 'ls'
