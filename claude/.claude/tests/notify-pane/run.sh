#!/usr/bin/env bash
# notify-pane lib + hook test runner.
# Iterates cases/*.sh; each case sources helpers.sh and uses assert_* helpers.
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_HOME="$HERE"
export LIB="$HERE/../../lib/notify-pane.sh"
export HOOK="$HERE/../../hooks/notify.sh"

[[ -f "$LIB" ]] || { echo "missing lib: $LIB" >&2; exit 2; }

pass=0; fail=0; failed_cases=()
for case in "$HERE"/cases/*.sh; do
  [[ -e "$case" ]] || continue
  name="$(basename "$case" .sh)"
  if ( cd "$HERE" && bash "$case" ); then
    printf "  PASS  %s\n" "$name"; pass=$((pass+1))
  else
    printf "  FAIL  %s\n" "$name"; fail=$((fail+1)); failed_cases+=("$name")
  fi
done

printf "\nnotify-pane: %d passed, %d failed\n" "$pass" "$fail"
if (( fail > 0 )); then
  printf "failed cases: %s\n" "${failed_cases[*]}"
  exit 1
fi
exit 0
