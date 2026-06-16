#!/usr/bin/env bash
# portability.sh — cross-platform fallbacks for macOS/Linux hooks.
#
# macOS system bash 3.2 lacks EPOCHSECONDS, and BSD stat uses `-f %m` where GNU
# uses `-c %Y`. Source this file; do not execute it directly.

# Seed EPOCHSECONDS on bash < 5.0 (macOS system bash) so callers can rely on it.
: "${EPOCHSECONDS:=$(date +%s)}"

# Print a file's mtime as a Unix timestamp, portably (GNU then BSD stat).
# Arguments: $1 file path
# Outputs:   the mtime epoch seconds on stdout, or 0 if stat fails
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# Run a command under a wall-clock timeout, portably.
# Prefers GNU `timeout`; falls back to a perl alarm where timeout is absent.
# Arguments: $1 timeout (seconds), $2.. command + args to run
# Outputs:   the command's own stdout/stderr
# Returns:   the command's exit status, or 124 (timeout) when it is killed
run_timeout() {
  local t=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$t" "$@"
  else
    perl -e 'alarm shift @ARGV; exec @ARGV' "$t" "$@"
  fi
}
