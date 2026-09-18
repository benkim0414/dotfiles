#!/usr/bin/env bash
# Stow hygiene test.
#
# A package's tests/ directory is repo-internal and must never reach the home
# directory. Stow links every top-level entry of a package, so a package
# carrying tests/ leaks it to ~/tests unless a .stow-local-ignore excludes it.
# That is exactly what happened to the zsh package, whose tests/ tree-folded
# into ~/tests and sat there unnoticed.
#
# Simulating into a throwaway target rather than ~ keeps the real home
# directory untouched and makes the output reflect a clean install instead of
# whatever links already exist.
#
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"

command -v stow >/dev/null 2>&1 || { echo "stow required" >&2; exit 2; }
[[ -d "$REPO/.git" || -f "$REPO/.git" ]] || { echo "not a repo root: $REPO" >&2; exit 2; }

fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

TARGET="$(mktemp -d)"
trap 'rm -rf "$TARGET"' EXIT

checked=0
for pkg_dir in "$REPO"/*/; do
  pkg="$(basename "$pkg_dir")"
  # docs/ is documentation, not a Stow package.
  [[ "$pkg" == "docs" ]] && continue
  [[ -d "$pkg_dir/tests" ]] || continue
  checked=$((checked + 1))

  # Capture first, then match. Piping stow directly into `grep -q` makes the
  # pipeline fail under `set -o pipefail`: grep exits at the first match, stow
  # dies of SIGPIPE, and the non-zero status reads as "no match" -- reporting
  # ok for a package that does leak.
  out="$(stow -n -v -d "$REPO" -t "$TARGET" "$pkg" 2>&1)"

  # Any action placing something at the target's top-level tests means this
  # package would put its fixtures in the home directory.
  if grep -qE '^(LINK|MKDIR): tests(/|$| )' <<<"$out"; then
    bad "$pkg would stow tests/ into the target; add .stow-local-ignore"
  else
    ok "$pkg does not stow tests/"
  fi
done

# A loop that matched nothing would report no failures and look like success.
# Assert it actually examined something.
if [[ $checked -gt 0 ]]; then
  ok "$checked package(s) carrying tests/ were checked"
else
  bad "no package with a tests/ directory found; this check verified nothing"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "stow-hygiene: all passed"
else
  echo "stow-hygiene: FAILURES"
fi
exit $fail
