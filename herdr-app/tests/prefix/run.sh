#!/usr/bin/env bash
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --test "$HERE/shortcuts.test.mjs"
