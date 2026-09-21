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

# Lowercase a string, portably.
#
# `${var,,}` is bash 4+. The hooks are invoked as `bash <path>` from
# settings.json, so the interpreter is whatever `bash` resolves to on PATH --
# on macOS that is /bin/bash 3.2.57, where `${var,,}` raises "bad substitution"
# at expansion time. That failure is near-silent: the message goes to the
# hook's stderr, the surrounding `if` sees an empty string, and the check it
# guards simply never matches. `tr` costs a subprocess, which is noise beside
# the jq forks these hooks already pay.
# Arguments: $1 string
# Outputs:   the string, lowercased
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
