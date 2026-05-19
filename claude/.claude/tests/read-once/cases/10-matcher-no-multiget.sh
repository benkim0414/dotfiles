#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
# Verify the active matcher string in settings.base.json excludes multi_get.
settings="$(dirname "${BASH_SOURCE[0]}")/../../../settings.base.json"
matcher="$(jq -r '
  .hooks.PreToolUse[]
  | select(.hooks[]?.command | tostring | test("read-once.sh"))
  | .matcher
' "$settings")"
if echo "$matcher" | grep -q 'mcp__qmd__multi_get'; then
  echo "  matcher still contains mcp__qmd__multi_get: $matcher" >&2
  exit 1
fi
echo "$matcher" | grep -q 'mcp__qmd__get' \
  || { echo "  matcher should still contain mcp__qmd__get: $matcher" >&2; exit 1; }
