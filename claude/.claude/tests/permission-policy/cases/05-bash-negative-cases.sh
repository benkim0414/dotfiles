#!/usr/bin/env bash
# Regression guard: common safe commands must never trip the lib checks.
set -uo pipefail
source "$TEST_HOME/helpers.sh"

assert_bash_silent 'git status'
assert_bash_silent 'git diff'
assert_bash_silent 'npm test'
assert_bash_silent 'pytest -q'
assert_bash_silent 'ls -la /tmp/'
assert_bash_silent 'cat /etc/hostname'
assert_bash_silent 'echo hi'
assert_bash_silent 'mkdir -p /tmp/x && cd /tmp/x && touch y'
assert_bash_silent 'curl https://api.github.com/repos/foo/bar'
assert_bash_silent 'curl https://example.com | jq .'
assert_bash_silent 'tar -czf out.tgz src/'
assert_bash_silent 'find . -name "*.md"'
