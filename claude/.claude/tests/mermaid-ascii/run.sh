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

echo "stow"

# Dry runs only (-n), into temp homes. Stow folds a target directory that
# does not exist into one link and never looks inside it, so each home
# pre-creates the render directory as a real one: Stow must descend into it
# and name what it would link there.
PKG_PARENT="$(cd "$HERE/../../../.." && pwd)"
STOW_IGNORE="$PKG_PARENT/claude/.stow-local-ignore"
[[ -f "$STOW_IGNORE" ]] || { bad "missing $STOW_IGNORE; the stow checks cannot run"; exit 1; }

# dry_stow <dir> <home> <pkg>: sets $out and $code. Captured, then matched:
# piping stow into `grep -q` under pipefail reads a match as a miss.
dry_stow() {
  out="$(stow -n -v -d "$1" -t "$2" "$3" 2>&1)"
  code=$?
}

if ! command -v stow >/dev/null 2>&1; then
  echo "stow required" >&2; exit 2
fi

mkdir -p "$TMP/home/.claude/mods/mermaid-ascii/render"
dry_stow "$PKG_PARENT" "$TMP/home" claude
if [[ $code -ne 0 ]]; then
  bad "stow claude: exit $code"; printf '%s\n' "$out" | sed 's/^/       /'
elif ! grep -q 'mermaid-ascii/render/render\.mjs' <<<"$out"; then
  bad "stow claude: never reached render/ (render.mjs not named)"
elif grep -q 'node_modules' <<<"$out"; then
  bad "stow claude: would link node_modules"
else
  ok "stow claude: links render.mjs, not node_modules"
fi

# Stow's defaults, checked on an isolated package so the result does not
# depend on what the real one holds today.
fixture() {
  rm -rf "$TMP/fx"
  mkdir -p "$TMP/fx/pkg/.claude/mods/x/render" "$TMP/fx/home/.claude/mods/x/render"
  : >"$TMP/fx/pkg/.claude/mods/x/render/keep.txt"
  : >"$TMP/fx/pkg/.claude/mods/x/render/notes.txt~"
}

fixture
cp "$STOW_IGNORE" "$TMP/fx/pkg/.stow-local-ignore"
dry_stow "$TMP/fx" "$TMP/fx/home" pkg
if [[ $code -ne 0 ]]; then
  bad "defaults: stow exit $code"
elif ! grep -q 'keep\.txt' <<<"$out"; then
  bad "defaults: never reached render/ (keep.txt not named)"
elif grep -q 'notes\.txt~' <<<"$out"; then
  bad "defaults: a backup file (.+~) would be linked"
else
  ok "defaults: backup file ignored"
fi

# The same fixture without the .+~ rule must link the backup file, or the
# check above was not testing anything.
fixture
grep -vxF '.+~' "$STOW_IGNORE" >"$TMP/fx/pkg/.stow-local-ignore"
dry_stow "$TMP/fx" "$TMP/fx/home" pkg
if [[ $code -eq 0 ]] && grep -q 'notes\.txt~' <<<"$out"; then
  ok "defaults: without .+~ the backup file is linked (check can fail)"
else
  bad "defaults: without .+~ the backup file is still not linked (exit $code)"
fi

echo
if [[ $fail -eq 0 ]]; then echo "mermaid-ascii: all passed"; else echo "mermaid-ascii: FAILURES"; fi
exit $fail
