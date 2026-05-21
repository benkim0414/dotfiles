#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Anchor: CONTAINER_NAMES must contain the universal entries.
( source "$LIB"
  for required in docs src lib tests packages apps; do
    found=0
    for c in "${CONTAINER_NAMES[@]}"; do
      [[ "$c" == "$required" ]] && { found=1; break; }
    done
    [[ $found -eq 1 ]] || { echo "  CONTAINER_NAMES missing required entry: $required" >&2; exit 1; }
  done
)

# Guarantee: lib file must not contain framework-name literals as standalone
# array tokens or quoted strings. Word-boundary match catches the literal
# anywhere on a line, including mid-line additions like
#   CONTAINER_NAMES=(docs doc spec src ...)
# Excludes occurrences inside comments to keep documentation freedom.
banned_literals=(spec plan openspec dotfiles proposal rfc prd)
for lit in "${banned_literals[@]}"; do
  # Strip comments, then word-boundary match
  if grep -E "^[^#]*\b${lit}\b" "$LIB" | grep -qE "(^|[[:space:](\"'])${lit}([[:space:])\"',]|$)"; then
    echo "  lib contains framework-name literal '$lit' (repo-agnostic violation)" >&2
    exit 1
  fi
done
