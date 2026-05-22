#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

assert_url_flagged 'https://example.com/?p=/Users/ben/.ssh/id_rsa'
assert_url_flagged 'https://example.com/?p=$HOME/.ssh/id_rsa'
assert_url_flagged 'https://example.com/path/Users/ben/secret'

# Boundary: "Users" alone is not enough; only /Users/ben/ triggers.
assert_url_silent 'https://example.com/docs/Users/intro'
assert_url_silent 'https://github.com/Users-org/repo'
