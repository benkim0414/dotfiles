#!/usr/bin/env bash
# Sourced by every case. Sandboxed HOME + git fixtures for the arming hook.
set -uo pipefail

: "${HOOK:?HOOK must be set by run.sh}"

# Physical path — see the note in tests/worktree-guard/helpers.sh and
# tests/session-lib/helpers.sh:12. An unresolved /var/folders path makes
# worktree_kind misread a main checkout as linked, so the hook would skip
# arming and case 00 would fail for the wrong reason.
CASE_TMP="$(cd "$(mktemp -d -t arm-guard-test.XXXXXX)" && pwd -P)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

export HOME="$CASE_TMP/home"
export STATE_DIR="$HOME/.claude/session-worktrees"
mkdir -p "$STATE_DIR"

SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

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

add_linked_worktree() {
  local dir="$1" name="$2"
  (cd "$dir" && git worktree add -q -b "wt-$name" ".claude/worktrees/$name" >/dev/null 2>&1)
  printf '%s' "$dir/.claude/worktrees/$name"
}

# session_start_json [session_id]
session_start_json() {
  jq -cn --arg s "${1:-$SID}" '{session_id:$s, hook_event_name:"SessionStart"}'
}

# run_arm <cwd> <json>  -- runs the hook, discards output, echoes exit status
run_arm() {
  local dir="$1" json="$2"
  (
    cd "$dir" && printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
    echo $?
  )
}

marker_exists() { [[ -f "$STATE_DIR/pending-$SID" ]]; }

assert_marker_present() {
  marker_exists || {
    echo "  expected marker $STATE_DIR/pending-$SID to exist" >&2
    exit 1
  }
}

assert_marker_absent() {
  if marker_exists; then
    echo "  expected no marker at $STATE_DIR/pending-$SID" >&2
    exit 1
  fi
}
