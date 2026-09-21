#!/usr/bin/env bash
# arm-worktree-guard.sh — arm the worktree guard for this session.
#
# Event:   SessionStart
# Matcher: n/a
# Exit:    0 always (SessionStart must not block; emits context JSON)
#
# Writes the pending-<session-id> marker that worktree-guard.sh blocks on,
# but only in a main working tree. worktree-entered.sh removes it when
# EnterWorktree runs. This is the only writer of that marker — deleting this
# hook disables worktree isolation silently, so tests/arm-worktree-guard/
# asserts the marker is actually created.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)
SESSION_ID=$(parse_session_id "$INPUT")

# No session id — the marker is keyed by it, so isolation is unavailable.
[[ -n "$SESSION_ID" ]] || exit 0

# Not a git repo, or a bare one: nothing to isolate.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && exit 0

# Already isolated — do not arm.
[[ "$(worktree_kind)" == "linked" ]] && exit 0

mkdir -p "$STATE_DIR"
# Sweep markers from sessions abandoned more than 24 hours ago.
find "$STATE_DIR" -name 'pending-*' -mmin +1440 -delete 2>/dev/null || true

touch "$STATE_DIR/pending-${SESSION_ID}"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
emit_context_with_msg "SessionStart" \
  "Main worktree (branch: ${BRANCH}). Call EnterWorktree() before any edits." \
  "[git-workflow] Main worktree (branch: ${BRANCH}). Call EnterWorktree() before any edits."
