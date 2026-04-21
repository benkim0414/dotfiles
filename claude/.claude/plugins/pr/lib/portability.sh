#!/usr/bin/env bash
# Portable fallbacks for macOS (system bash 3.2 lacks EPOCHSECONDS; BSD stat
# uses -f %m instead of GNU -c %Y).
# Source this file; do not execute it directly.
: "${EPOCHSECONDS:=$(date +%s)}"
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
# Portable timeout: prefer GNU timeout, fall back to perl alarm.
run_timeout() {
  local t=$1; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$t" "$@"
  else
    perl -e 'alarm shift @ARGV; exec @ARGV' "$t" "$@"
  fi
}
