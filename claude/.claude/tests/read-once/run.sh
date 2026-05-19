#!/usr/bin/env bash
# Read-once hook test runner.
# Iterates cases/*.sh; each case sources helpers.sh and uses assert_* helpers.
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_HOME="$HERE"
export HOOK="$HERE/../../hooks/read-once.sh"
export LIB="$HERE/../../lib/read-once-cache.sh"

[[ -f "$HOOK" ]] || { echo "missing hook: $HOOK" >&2; exit 2; }
[[ -f "$LIB"  ]] || { echo "missing lib: $LIB"   >&2; exit 2; }

pass=0; fail=0; failed_cases=()
for case in "$HERE"/cases/*.sh; do
  [[ -e "$case" ]] || continue
  name="$(basename "$case" .sh)"
  if ( cd "$HERE" && bash "$case" ); then
    printf "  PASS  %s\n" "$name"
    pass=$((pass+1))
  else
    printf "  FAIL  %s\n" "$name"
    fail=$((fail+1))
    failed_cases+=("$name")
  fi
done

printf "\n%d passed, %d failed\n" "$pass" "$fail"
if (( fail > 0 )); then
  printf "failed cases: %s\n" "${failed_cases[*]}"
  exit 1
fi
