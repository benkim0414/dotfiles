#!/usr/bin/env bash
# Output-style wiring test.
#
# outputStyle resolves against the style file's `name` frontmatter, matched
# exactly and case-sensitively; the filename is ignored when `name` is
# present. A mismatch makes Claude Code fall back to the Default style with
# no warning and no error, so this agreement is asserted rather than
# eyeballed. Verified empirically -- see the design spec.
#
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(cd "$HERE/../.." && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
STYLE="$CLAUDE_DIR/output-styles/readable.md"
BASE="$CLAUDE_DIR/settings.base.json"
OVERLAY="$CLAUDE_DIR/settings.overlay.json"
LOCAL="$REPO/.claude/settings.local.json"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }
[[ -f "$BASE" ]] || { echo "missing $BASE" >&2; exit 2; }

fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

if [[ ! -f "$STYLE" ]]; then
  bad "missing $STYLE"
  echo
  echo "output-style: FAILURES"
  exit 1
fi

# An unterminated block is not frontmatter at all: Claude Code parses none of
# it and falls back to the filename stem, which is the silent failure this
# suite exists to catch. Assert the closing delimiter before trusting any
# value read out of the block.
if awk '
  NR == 1 && $0 == "---" { open = 1; next }
  open && $0 == "---"    { closed = 1; exit }
  END                    { exit !(open && closed) }
' "$STYLE"; then
  ok "frontmatter block opens on line 1 and is terminated"
else
  bad "frontmatter block is missing or has no closing ---"
fi

# Read one scalar out of the leading --- frontmatter block. Surrounding
# quotes are stripped because `name: "Readable"` is legal YAML and means the
# same thing; \042 and \047 are " and ' written so the shell does not fight
# the awk program over quoting.
fm() {
  awk -v key="$1" '
    NR == 1 && $0 == "---" { inblock = 1; next }
    inblock && $0 == "---" { exit }
    inblock {
      idx = index($0, ":")
      if (idx == 0) next
      k = substr($0, 1, idx - 1)
      v = substr($0, idx + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      gsub(/^[\042\047]|[\042\047]$/, "", v)
      if (k == key) { print v; exit }
    }
  ' "$STYLE"
}

# Lowercase without ${x,,}: that is a bash 4 expansion, and `bash` on macOS
# is 3.2.
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Without this field a custom style discards Claude Code's built-in
# software-engineering instructions, and nothing reports that it happened.
# YAML accepts True and TRUE, so compare case-insensitively.
kci="$(fm keep-coding-instructions)"
if [[ "$(lower "$kci")" == "true" ]]; then
  ok "keep-coding-instructions = $kci"
else
  bad "keep-coding-instructions = '${kci:-<unset>}' (want true)"
fi

style_name="$(fm name)"
if [[ -n "$style_name" ]]; then
  ok "style name = $style_name"
else
  bad "style declares no name frontmatter"
fi

# The selection must equal the name exactly. Case matters: a lowercased
# value resolves to nothing and falls back to Default.
base_sel="$(jq -r '.outputStyle // empty' "$BASE")"
if [[ -n "$style_name" && "$base_sel" == "$style_name" ]]; then
  ok "settings.base.json outputStyle = $base_sel"
else
  bad "settings.base.json outputStyle = '${base_sel:-<unset>}' (want '${style_name:-<name unset>}', exact case)"
fi

# claude-sync folds the overlay over the base, so confirm the overlay does
# not change the selection out from under us.
if [[ -f "$OVERLAY" ]]; then
  merged_sel="$(jq -s -r '(.[0] * .[1]).outputStyle // empty' "$BASE" "$OVERLAY")"
  if [[ -n "$style_name" && "$merged_sel" == "$style_name" ]]; then
    ok "survives the base+overlay merge as $merged_sel"
  else
    bad "overlay changes outputStyle to '${merged_sel:-<unset>}'"
  fi
fi

# The /output-style picker and /config both write their selection to
# project-level .claude/settings.local.json, which outranks the user-level
# settings.json that claude-sync generates. One picker invocation here would
# silently pin this repo to another style.
if [[ -f "$LOCAL" ]]; then
  local_sel="$(jq -r '.outputStyle // empty' "$LOCAL" 2>/dev/null)"
  if [[ -z "$local_sel" || "$local_sel" == "$style_name" ]]; then
    ok "project settings.local.json does not override outputStyle"
  else
    bad "project settings.local.json sets outputStyle = '$local_sel', which outranks the user level"
  fi
else
  ok "no project settings.local.json to override outputStyle"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "output-style: all passed"
else
  echo "output-style: FAILURES"
fi
exit $fail
