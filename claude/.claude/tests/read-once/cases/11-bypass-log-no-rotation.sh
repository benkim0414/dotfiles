#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
hook="$(dirname "${BASH_SOURCE[0]}")/../../../hooks/read-once.sh"
if grep -qE 'mv "\$_log_file" "\$\{_log_file\}\.1"' "$hook"; then
  echo "  bypass-log rotation block is still present in hook" >&2
  exit 1
fi
