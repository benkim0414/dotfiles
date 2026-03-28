#!/usr/bin/env bash
# Portable fallbacks for macOS (system bash 3.2 lacks EPOCHSECONDS; BSD stat
# uses -f %m instead of GNU -c %Y).
# Source this file; do not execute it directly.
: "${EPOCHSECONDS:=$(date +%s)}"
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
