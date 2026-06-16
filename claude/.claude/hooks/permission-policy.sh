#!/usr/bin/env bash
# permission-policy.sh — semantic permission policy; dispatch by tool_name.
#
# Event:   PreToolUse
# Matcher: Bash|Write|Edit|NotebookEdit|WebFetch
# Exit:    0 always — silent = allow, or emits {permissionDecision:"ask"} JSON
#          when a lib check fires. Never emits deny. Off: CLAUDE_PERMISSION_POLICY=off
#
# Reads stdin JSON and delegates to the matcher functions in
# lib/permission-policy.sh (check_bash / check_file_edit / check_web_fetch).
set -uo pipefail

# Honor disable env var. Positioned before all I/O and lib sourcing so a
# broken or missing lib never blocks the kill-switch.
if [[ "${CLAUDE_PERMISSION_POLICY:-}" == "off" ]]; then
  exit 0
fi

INPUT=$(cat)

# Extract tool name once. Missing/non-JSON input -> silent allow.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
[[ -z "$TOOL" ]] && exit 0

# Fast-exit for tools we do not inspect (Read, Glob, Grep, Task, etc.).
# Avoids sourcing the lib for ~70%+ of tool calls in a typical session.
case "$TOOL" in
  Bash | Write | Edit | NotebookEdit | WebFetch) ;;
  *) exit 0 ;;
esac

# Guard against missing or broken lib -- never block Claude Code with stderr noise.
LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/permission-policy.sh"
[[ -f "$LIB" ]] || exit 0
# shellcheck source=../lib/permission-policy.sh
source "$LIB"

REASON=""
case "$TOOL" in
  Bash)
    CMD=$(jq -r '.tool_input.command // ""' <<<"$INPUT")
    REASON="$(check_bash "$CMD")"
    ;;
  Write | Edit | NotebookEdit)
    FILE_PATH=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$INPUT")
    REASON="$(check_file_edit "$FILE_PATH" "${CLAUDE_WORKTREE_ROOT:-}")"
    ;;
  WebFetch)
    URL=$(jq -r '.tool_input.url // ""' <<<"$INPUT")
    REASON="$(check_web_fetch "$URL")"
    ;;
esac

if [[ -n "$REASON" ]]; then
  jq -cn --arg r "$REASON" \
    '{hookSpecificOutput: {hookEventName:"PreToolUse", permissionDecision:"ask", permissionDecisionReason:$r}}'
fi
exit 0
