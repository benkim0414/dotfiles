#!/usr/bin/env bash
# Sourced by every case. Provides assertions + git-fixture setup for session.sh.
set -uo pipefail

: "${LIB:?LIB must be set by run.sh}"

# Resolve to the physical path: on macOS mktemp lives under /var -> /private/var
# symlink. worktree_kind compares `git rev-parse --absolute-git-dir` (physical)
# against `cd <git-common-dir> && pwd` (logical); a symlinked temp root makes
# the two differ and misreports a main repo as linked. Pinning the fixture to a
# physical path keeps the comparison honest without altering the helper.
CASE_TMP="$(cd "$(mktemp -d -t session-lib-test.XXXXXX)" && pwd -P)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# assert_eq <want> <got> [msg]
assert_eq() {
  local want="$1" got="$2" msg="${3:-assert_eq}"
  [[ "$got" == "$want" ]] || { echo "  $msg: want='$want' got='$got'" >&2; exit 1; }
}

# init_main_repo <dir> -- a primary working tree with one commit.
init_main_repo() {
  local dir="$1"
  ( cd "$dir" \
    && git init -q -b main \
    && git config user.email "test@example.com" \
    && git config user.name "Test" \
    && git config core.hooksPath /dev/null \
    && git commit -q --allow-empty -m "seed" )
}

# add_linked_worktree <repo> <wt> -- adds a linked worktree at <wt>.
add_linked_worktree() {
  local repo="$1" wt="$2"
  ( cd "$repo" && git worktree add -q -b feature "$wt" >/dev/null 2>&1 )
}
