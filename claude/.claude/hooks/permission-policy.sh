#!/usr/bin/env bash
# PreToolUse hook: semantic permission policy. Reads stdin JSON, dispatches by
# tool_name, emits {permissionDecision: "ask"} JSON when a lib check fires.
# Exit 0 silent = allow. Never emits deny.
#
# Disable with: CLAUDE_PERMISSION_POLICY=off (returns 0 immediately).
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
  Bash|Write|Edit|MultiEdit|NotebookEdit|WebFetch) ;;
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
  Write|Edit|MultiEdit|NotebookEdit)
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
