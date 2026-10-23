#!/usr/bin/env bash
# mermaid-ascii converter test.
#
# Runs the mod's render.mjs the way the hooks module does (node, source on
# stdin) and checks its exit-code contract: 0 with box-drawing art, 1 for a
# diagram the library refuses, 3 when beautiful-mermaid is not installed.
#
# Exits 0 if all pass, 1 on any failure, 2 when it cannot check (no node, or
# `npm ci` has not run), so "could not check" never reads as "passed".
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER="$(cd "$HERE/../../mods/mermaid-ascii/render" && pwd)"

command -v node >/dev/null 2>&1 || { echo "node required" >&2; exit 2; }
[[ -f "$RENDER/render.mjs" ]] || { echo "missing $RENDER/render.mjs" >&2; exit 2; }
[[ -f "$RENDER/node_modules/beautiful-mermaid/package.json" ]] || {
  echo "beautiful-mermaid not installed: npm ci --prefix $RENDER" >&2; exit 2;
}

fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# render <dir> <source>: runs render.mjs from <dir>, setting $out and $code.
render() {
  out="$(printf '%s\n' "$2" | env -u NODE_PATH node "$1/render.mjs" 2>/dev/null)"
  code=$?
}

echo "converter"

flowchart=$'flowchart LR\n  A[Start] --> B{Ok?}\n  B -->|yes| C[Done]'
sequence=$'sequenceDiagram\n  A->>B: hi\n  B-->>A: ok'
state=$'stateDiagram-v2\n  [*] --> Idle\n  Idle --> Busy'
esc=$'\x1b'

for name in flowchart sequence state; do
  render "$RENDER" "${!name}"
  if [[ $code -ne 0 ]]; then
    bad "$name: exit $code, expected 0"
    continue
  fi
  if [[ -z "$out" ]]; then
    bad "$name: empty stdout"
  # Substrings, not a bracket class: a class over multibyte characters
  # matches single bytes under a C locale.
  elif [[ "$out" != *─* && "$out" != *│* && "$out" != *┌* ]]; then
    bad "$name: no box-drawing character in the art"
  elif [[ "$out" == *"$esc"* ]]; then
    bad "$name: art holds an ESC byte"
  else
    ok "$name: exit 0, box-drawing art, no ESC"
  fi
done

render "$RENDER" $'garbage here\n  A --> B'
if [[ $code -eq 1 && -z "$out" ]]; then
  ok "invalid diagram: exit 1, empty stdout"
else
  bad "invalid diagram: exit $code, stdout ${#out} bytes; expected 1 and empty"
fi

# A copy beside no node_modules finds no package, however the real one is set up.
mkdir -p "$TMP/bare"
cp "$RENDER/render.mjs" "$TMP/bare/"
render "$TMP/bare" "$flowchart"
if [[ $code -eq 3 ]]; then
  ok "package missing: exit 3"
else
  bad "package missing: exit $code, expected 3"
fi

echo
if [[ $fail -eq 0 ]]; then echo "mermaid-ascii: all passed"; else echo "mermaid-ascii: FAILURES"; fi
exit $fail
