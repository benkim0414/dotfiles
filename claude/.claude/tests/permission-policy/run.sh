#!/usr/bin/env bash
# Permission-policy lib + hook test runner.
# Iterates cases/*.sh; each case sources helpers.sh.
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_HOME="$HERE"
export LIB="$HERE/../../lib/permission-policy.sh"
export HOOK="$HERE/../../hooks/permission-policy.sh"

[[ -f "$LIB"  ]] || { echo "missing lib: $LIB"   >&2; exit 2; }

pass=0; fail=0; failed_cases=()
for case in "$HERE"/cases/*.sh; do
  [[ -e "$case" ]] || continue
  name="$(basename "$case" .sh)"
  printf '  case %s ... ' "$name"
  if ( bash "$case" ); then
    printf 'PASS\n'; pass=$((pass+1))
  else
    printf 'FAIL\n'; fail=$((fail+1)); failed_cases+=("$name")
  fi
done

echo
echo "permission-policy: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]] || { printf '  failed: %s\n' "${failed_cases[@]}"; exit 1; }
exit 0
