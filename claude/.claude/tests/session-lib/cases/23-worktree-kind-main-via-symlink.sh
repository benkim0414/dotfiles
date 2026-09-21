#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# A MAIN checkout whose path is reached through a symlink must still report
# "main". git rev-parse --absolute-git-dir resolves symlinks; `cd ... && pwd`
# does not, so an asymmetric comparison reports "linked" here and silently
# disables worktree isolation.
#
# This case deliberately does NOT canonicalise: the unresolved path IS the
# input under test. helpers.sh canonicalises CASE_TMP, so build the
# unresolved path explicitly.
raw="$(mktemp -d -t wk-symlink.XXXXXX)"
trap 'rm -rf "$raw"' EXIT
mkdir -p "$raw/repo"
(
  cd "$raw/repo" \
    && git init -q -b main \
    && git config user.email "test@example.com" \
    && git config user.name "Test" \
    && git config core.hooksPath /dev/null \
    && git commit -q --allow-empty -m "chore(seed): initial"
)

got=$(cd "$raw/repo" && source "$LIB" && worktree_kind)
[[ "$got" == "main" ]] \
  || {
    echo "  worktree_kind returned '$got' for a main checkout reached via a symlink; want 'main'" >&2
    exit 1
  }
