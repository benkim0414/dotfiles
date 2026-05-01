#!/usr/bin/env bash
# Shared cache helpers for read-once.sh.
# Source this file after setting globals: CACHE CACHE_DIR TTL NOW SESSION_ID

# Append a JSONL entry to CACHE for ABS with the given ranges array.
# Args: abs mtime ranges (JSON array string)
rc_record() {
  local abs="$1" mtime="$2" ranges="$3"
  jq -cn \
    --arg path "$abs" \
    --argjson mtime "$mtime" \
    --argjson ranges "$ranges" \
    --argjson ts "$NOW" \
    '{path:$path,mtime:$mtime,ranges:$ranges,ts:$ts}' \
    >> "$CACHE" 2>/dev/null || true
}

# Look up ABS in the JSONL cache and emit tab-separated:
#   STATUS<TAB>P_MTIME<TAB>P_TS<TAB>COVERED<TAB>EXTENDED
# STATUS=NEW when no prior entry, HIT otherwise.
# EXTENDED is the prior ranges array extended with the new [offset,limit].
# Uses /dev/null when CACHE does not exist (jq sees an empty stream → NEW).
rc_lookup() {
  local abs="$1" offset="$2" limit="$3"
  local cache_file="${CACHE:-/dev/null}"
  [[ -f "$cache_file" ]] || cache_file=/dev/null
  jq -rs --arg p "$abs" --argjson o2 "$offset" --argjson l2 "$limit" '
    [.[] | select(.path == $p)] | last as $prior |
    if $prior == null then "NEW\t0\t0\tfalse\t[]"
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
      "HIT\t\($prior.mtime)\t\($prior.ts)\t\($cov)\t\($prior.ranges + [[$o2, $l2]] | tojson)"
    end
  ' "$cache_file" 2>/dev/null || true
}

# Write the permissionDecision=deny JSON to stdout.
# Args: abs age_seconds size_bytes
# Reads TTL from the global env.
rc_deny() {
  local abs="$1" age="$2" size="$3"
  local tokens
  tokens=$(( size / 4 ))
  local reason="read-once: ${abs} already in context (read ${age}s ago, unchanged, ~${tokens} tokens). Use the content already loaded earlier in this conversation. To invalidate: edit the file, or request a different offset/limit."
  jq -cn --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
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
