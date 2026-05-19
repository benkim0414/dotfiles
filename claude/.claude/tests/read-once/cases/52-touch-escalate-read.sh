#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"

# Seed cache.
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null

# Pretend a touch happened (skip block by writing the sidecar directly).
# The hook stores resolved (realpath -m) paths, so resolve here too.
sidecar="$CASE_TMP/claude/touch-events-$SESSION_ID.jsonl"
mkdir -p "$(dirname "$sidecar")"
abs="$(realpath -m "$tmpf" 2>/dev/null \
      || grealpath -m "$tmpf" 2>/dev/null \
      || readlink -f "$tmpf" 2>/dev/null \
      || echo "$tmpf")"
jq -cn --arg p "$abs" --argjson ts "$(date +%s)" \
  '{path:$p,ts:$ts,event:"touch_invalidate"}' >> "$sidecar"

# Next read deny must escalate to the touch-detected wording.
out="$(printf '%s' "$payload" | run_hook)"
assert_deny "$out"
assert_deny_contains "$out" "Touch invalidation detected"
