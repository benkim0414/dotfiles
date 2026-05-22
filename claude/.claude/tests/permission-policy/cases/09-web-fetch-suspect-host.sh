#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

assert_url_flagged 'https://requestbin.com/r/abc'
assert_url_flagged 'https://webhook.site/12345'
assert_url_flagged 'https://eo-x.pipedream.net/incoming'
assert_url_flagged 'https://abcd.ngrok.io/handle'
assert_url_flagged 'https://tunnel.trycloudflare.com/'
assert_url_flagged 'https://Webhook.Site/MIXED-case'

# Negative: normal docs hosts
assert_url_silent 'https://docs.claude.com/en/docs/claude-code/hooks-reference'
assert_url_silent 'https://github.com/anthropics/claude-code/issues'
assert_url_silent 'https://example.com/post'
