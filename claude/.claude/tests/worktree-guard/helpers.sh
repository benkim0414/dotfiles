#!/usr/bin/env bash
# Sourced by every case. Provides a sandboxed HOME, git fixtures, and
# assertions for the worktree guard.
set -uo pipefail

: "${HOOK:?HOOK must be set by run.sh}"

# Resolve to the physical path: on macOS mktemp lives under /var -> /private/var.
# `git rev-parse --absolute-git-dir` resolves symlinks but `cd <dir> && pwd`
# does not, so an unresolved fixture path makes the guard read a main checkout
# as a linked worktree and allow the edit. Same convention, same reason, as
# claude/.claude/tests/session-lib/helpers.sh:12.
CASE_TMP="$(cd "$(mktemp -d -t worktree-guard-test.XXXXXX)" && pwd -P)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# Sandbox HOME so the hook never touches the real ~/.claude/session-worktrees.
export HOME="$CASE_TMP/home"
export STATE_DIR="$HOME/.claude/session-worktrees"
mkdir -p "$STATE_DIR"

# A valid-shaped session id; parse_session_id rejects anything else.
SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

# make_repo <dir>
# Creates a git repo with one commit so HEAD is valid.
make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  (cd "$dir" \
    && git init -q -b feature \
    && git config user.email "test@example.com" \
    && git config user.name "Test" \
    && git config core.hooksPath /dev/null \
    && git commit -q --allow-empty -m "chore(seed): initial")
}

# add_linked_worktree <repo-dir> <name>
# Creates <repo-dir>/.claude/worktrees/<name> on a new branch and echoes its path.
add_linked_worktree() {
  local dir="$1" name="$2"
  (cd "$dir" && git worktree add -q -b "wt-$name" ".claude/worktrees/$name" >/dev/null 2>&1)
  printf '%s' "$dir/.claude/worktrees/$name"
}

set_marker() { touch "$STATE_DIR/pending-$SID"; }
clear_marker() { rm -f "$STATE_DIR/pending-$SID"; }
marker_exists() { [[ -f "$STATE_DIR/pending-$SID" ]]; }

# guard_json <file_path> [session_id]
# Emits a PreToolUse Write payload.
guard_json() {
  local path="$1" sid="${2:-$SID}"
  jq -cn --arg p "$path" --arg s "$sid" \
    '{session_id:$s, tool_name:"Write", tool_input:{file_path:$p}}'
}

# guard_json_no_sid <file_path>
guard_json_no_sid() {
  jq -cn --arg p "$1" '{tool_name:"Write", tool_input:{file_path:$p}}'
}

# run_guard_status <cwd> <json>
# Runs the hook from <cwd> with the given payload; echoes the exit status.
run_guard_status() {
  local dir="$1" json="$2"
  (
    cd "$dir" && printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
    echo $?
  )
}

assert_status() {
  local want="$1" got="$2" what="$3"
  [[ "$got" == "$want" ]] \
    || {
      echo "  $what: want exit=$want got exit=$got" >&2
      exit 1
    }
}
