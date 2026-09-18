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
STYLE="$CLAUDE_DIR/output-styles/readable.md"
BASE="$CLAUDE_DIR/settings.base.json"
OVERLAY="$CLAUDE_DIR/settings.overlay.json"

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

# Read one scalar out of the leading --- frontmatter block.
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
      if (k == key) { print v; exit }
    }
  ' "$STYLE"
}

# Without this field a custom style discards Claude Code's built-in
# software-engineering instructions, and nothing reports that it happened.
kci="$(fm keep-coding-instructions)"
if [[ "$kci" == "true" ]]; then
  ok "keep-coding-instructions = true"
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

echo
if [[ $fail -eq 0 ]]; then
  echo "output-style: all passed"
else
  echo "output-style: FAILURES"
fi
exit $fail
