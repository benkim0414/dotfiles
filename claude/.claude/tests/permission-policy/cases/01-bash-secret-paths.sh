#!/usr/bin/env bash
# Lib-level: shell-expanded secret paths the regex-deny list misses must be flagged.
set -uo pipefail
source "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0")")/../helpers.sh"

# Positive: must flag
assert_bash_flagged 'cat $HOME/.ssh/id_rsa'
assert_bash_flagged 'cat ${HOME}/.ssh/id_rsa'
assert_bash_flagged 'cat /Users/ben/.ssh/id_rsa'
assert_bash_flagged 'cat /Users/ben/.ssh/id_ed25519'
assert_bash_flagged 'cp /Users/ben/.aws/credentials /tmp/leak'
assert_bash_flagged 'gpg --decrypt /Users/ben/.claude/.credentials.json'

# Negative: regular bash stays silent
assert_bash_silent 'ls /tmp'
assert_bash_silent 'echo hello'
assert_bash_silent 'cat README.md'
