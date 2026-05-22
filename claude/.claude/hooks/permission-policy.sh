#!/usr/bin/env bash
# PreToolUse hook: semantic permission policy. Reads stdin JSON, dispatches by
# tool_name, emits {permissionDecision: "ask"} JSON when a lib check fires.
# Exit 0 silent = allow. Never emits deny.
#
# Disable with: CLAUDE_PERMISSION_POLICY=off (returns 0 immediately).
set -uo pipefail

# Honor disable env var.
if [[ "${CLAUDE_PERMISSION_POLICY:-}" == "off" ]]; then
  exit 0
fi

# shellcheck source=../lib/permission-policy.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/permission-policy.sh"

INPUT=$(cat)

# Malformed input: never block.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
[[ -z "$TOOL" ]] && exit 0

REASON=""
case "$TOOL" in
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
    REASON="$(check_bash "$CMD")"
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')
    REASON="$(check_file_edit "$FILE_PATH" "${CLAUDE_WORKTREE_ROOT:-}")"
    ;;
  WebFetch)
    URL=$(printf '%s' "$INPUT" | jq -r '.tool_input.url // ""')
    REASON="$(check_web_fetch "$URL")"
    ;;
  *)
    exit 0
    ;;
esac

if [[ -n "$REASON" ]]; then
  jq -cn --arg r "$REASON" \
    '{hookSpecificOutput: {hookEventName:"PreToolUse", permissionDecision:"ask", permissionDecisionReason:$r}}'
fi
exit 0
