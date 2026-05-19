#!/usr/bin/env bash
# Sourced by every case. Provides setup, teardown, fixtures, assertions.

set -uo pipefail

: "${HOOK:?HOOK must be set by run.sh}"
: "${LIB:?LIB must be set by run.sh}"

CASE_TMP="$(mktemp -d -t read-once-test.XXXXXX)"
export XDG_RUNTIME_DIR="$CASE_TMP"
export READ_ONCE_DISABLE=0
export READ_ONCE_DIFF=0          # tests opt in per-case
export READ_ONCE_GC_DISABLE=1    # never prune during a single test
mkdir -p "$CASE_TMP/claude"

cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# fixture_session writes SESSION_ID to stdout
fixture_session() {
  # 30 bits of entropy via two $RANDOM rolls (BSD-portable; date +%s%N is GNU-only).
  printf '11111111-1111-1111-1111-%012x' "$((RANDOM * 32768 + RANDOM))"
}

# stdin_for TOOL FILE [OFFSET] [LIMIT] [COMMAND] [OUTPUT_MODE] -> JSON on stdout
stdin_for() {
  local tool="$1" file="${2:-}" offset="${3:-0}" limit="${4:--1}"
  local cmd="${5:-}" mode="${6:-}"
  jq -cn \
    --arg sid "$SESSION_ID" \
    --arg tool "$tool" \
    --arg fp "$file" \
    --argjson off "$offset" \
    --argjson lim "$limit" \
    --arg cmd "$cmd" \
    --arg mode "$mode" \
    '{session_id:$sid, tool_name:$tool,
      tool_input:{file_path:$fp, notebook_path:$fp, path:$fp,
                  offset:$off, limit:$lim, command:$cmd, output_mode:$mode}}'
}

# run_hook reads JSON from stdin, invokes the hook, prints stdout, returns exit code.
run_hook() { bash "$HOOK"; }

assert_exit() {
  local want="$1" got="$2"
  [[ "$want" == "$got" ]] || { echo "  exit want=$want got=$got" >&2; exit 1; }
}

assert_deny() {
  local out="$1"
  echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null \
    || { echo "  expected deny JSON, got: $out" >&2; exit 1; }
}

assert_allow() {
  local out="$1"
  [[ -z "$out" ]] || { echo "  expected silent allow, got: $out" >&2; exit 1; }
}

assert_deny_contains() {
  local out="$1" needle="$2"
  echo "$out" | jq -re '.hookSpecificOutput.permissionDecisionReason' \
    | grep -qF -- "$needle" \
    || { echo "  deny reason missing '$needle'; got: $out" >&2; exit 1; }
}

SESSION_ID="$(fixture_session)"
export SESSION_ID
