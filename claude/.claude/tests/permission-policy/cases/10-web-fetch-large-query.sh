#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Build a >500-char query string deterministically.
big=$(printf 'x%.0s' {1..600})
assert_url_flagged "https://example.com/?data=${big}"

# Base64-shaped payload (>=120 chars of [A-Za-z0-9+/])
b64=$(printf 'A%.0s' {1..130})
assert_url_flagged "https://example.com/?p=${b64}="

# Negative: short query strings stay silent
assert_url_silent 'https://example.com/?q=hello'
assert_url_silent 'https://docs.claude.com/en/docs?source=x'
