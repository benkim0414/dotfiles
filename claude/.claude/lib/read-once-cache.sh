#!/usr/bin/env bash
# Shared cache helpers for read-once.sh.
# Source this file after setting globals: CACHE CACHE_DIR TTL NOW SESSION_ID

# Append a JSONL entry to CACHE for ABS with the given ranges array.
# Args: abs mtime ranges (JSON array string) [denies]
# denies defaults to 0 (counter reset on every rc_record call).
rc_record() {
  local abs="$1" mtime="$2" ranges="$3" denies="${4:-0}"
  jq -cn \
    --arg path "$abs" \
    --argjson mtime "$mtime" \
    --argjson ranges "$ranges" \
    --argjson ts "$NOW" \
    --argjson denies "$denies" \
    '{path:$path,mtime:$mtime,ranges:$ranges,ts:$ts,denies:$denies}' \
    >> "$CACHE" 2>/dev/null || true
}

# Look up ABS in the JSONL cache and emit tab-separated:
#   STATUS<TAB>P_MTIME<TAB>P_TS<TAB>COVERED<TAB>EXTENDED<TAB>P_DENIES
# STATUS=NEW when no prior entry, HIT otherwise.
# EXTENDED is the prior ranges array extended with the new [offset,limit].
# P_DENIES is the deny counter for the latest entry, 0 if absent.
# Uses /dev/null when CACHE does not exist (jq sees an empty stream → NEW).
rc_lookup() {
  local abs="$1" offset="$2" limit="$3"
  local cache_file="${CACHE:-/dev/null}"
  [[ -f "$cache_file" ]] || cache_file=/dev/null
  jq -rs --arg p "$abs" --argjson o2 "$offset" --argjson l2 "$limit" '
    [.[] | select(.path == $p)] | last as $prior |
    if $prior == null then "NEW\t0\t0\tfalse\t[]\t0"
    else
      ([$prior.ranges[]? |
        .[0] as $o1 | .[1] as $l1 |
        if $o1 <= $o2 then
          if $l2 == -1 then ($l1 == -1)
          elif $l1 == -1 then true
          else ($o1 + $l1) >= ($o2 + $l2)
          end
        else false end
      ] | any) as $cov |
      "HIT\t\($prior.mtime)\t\($prior.ts)\t\($cov)\t\($prior.ranges + [[$o2, $l2]] | tojson)\t\($prior.denies // 0)"
    end
  ' "$cache_file" 2>/dev/null || true
}

# Write the permissionDecision=deny JSON to stdout.
# Args: abs age_seconds size_bytes [denies]
# denies is the count of prior denies on this (session, path); the wording
# escalates through ranks as it grows (see T13).
rc_deny() {
  local abs="$1" age="$2" size="$3" denies="${4:-0}"
  local tokens
  tokens=$(( size / 4 ))
  local n=$((denies + 1))
  local reason
  if   (( denies == 0 )); then
    reason="read-once: ${abs} in context (read ${age}s ago, unchanged, ~${tokens} tokens). Use loaded content. To invalidate: edit file or request different offset/limit."
  elif (( denies <= 2 )); then
    reason="read-once: ${abs} STILL in context (deny #${n}, read ${age}s ago). Stop re-reading. Use content already loaded OR change approach."
  elif (( denies <= 5 )); then
    reason="read-once: ${abs} DENY #${n}. File unchanged since first read. Re-reads will keep failing. Use content from context OR change task plan."
  else
    reason="read-once: ${abs} DENY #${n} — retry loop. Operator escape: set READ_ONCE_DISABLE=1 in env. Otherwise abandon this approach."
  fi
  jq -cn --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
}

# rc_recent_touch ABS [WINDOW_SECONDS]
# Returns 0 (and prints the touch ts) if abs was touched within WINDOW seconds
# of NOW; returns 1 otherwise. Default window: 30s.
rc_recent_touch() {
  local abs="$1" window="${2:-30}"
  local sidecar="${CACHE_DIR}/touch-events-${SESSION_ID}.jsonl"
  [[ -f "$sidecar" ]] || return 1
  local ts
  ts=$(jq -rs --arg p "$abs" --argjson now "$NOW" --argjson w "$window" '
    [.[]? // empty
     | select(.path == $p and (.ts // 0) >= ($now - $w))
     | .ts] | last // empty
  ' "$sidecar" 2>/dev/null)
  [[ -n "$ts" ]] || return 1
  printf '%s\n' "$ts"
  return 0
}

# Compute a stable filename slug from an absolute path (for snapshot storage).
# GNU sha1sum → BSD shasum → GNU md5sum → BSD md5, last resort base64 truncated.
rc_path_slug() {
  local abs="$1"
  printf '%s' "$abs" | sha1sum 2>/dev/null | cut -c1-40 && return
  printf '%s' "$abs" | shasum  2>/dev/null | cut -c1-40 && return
  printf '%s' "$abs" | md5sum  2>/dev/null | cut -c1-32 && return
  printf '%s' "$abs" | md5     2>/dev/null | tr -d ' \t\n' && return
  # Absolute fallback: base64, URL-safe chars only.
  printf '%s' "$abs" | base64 2>/dev/null | tr '/+=' '_-~' | head -c 64
}
