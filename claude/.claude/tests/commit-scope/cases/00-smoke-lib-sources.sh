#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Lib sources without error and exposes CONTAINER_NAMES.
( source "$LIB" && [[ ${#CONTAINER_NAMES[@]} -gt 0 ]] ) \
  || { echo "  lib failed to source or CONTAINER_NAMES empty" >&2; exit 1; }
