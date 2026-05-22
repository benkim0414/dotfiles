#!/usr/bin/env bash
# Sourced by every case. Provides assertions + JSON fixtures.
set -uo pipefail

: "${LIB:?LIB must be set by run.sh}"

CASE_TMP="$(mktemp -d -t permission-policy-test.XXXXXX)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# --- Lib-unit assertions ---------------------------------------------------

assert_bash_flagged() {
  local cmd="$1"
  local reason
  reason=$( source "$LIB" && check_bash "$cmd" )
  [[ -n "$reason" ]] \
    || { echo "  expected bash '$cmd' to be flagged; was not" >&2; exit 1; }
}

assert_bash_silent() {
  local cmd="$1"
  local reason
  reason=$( source "$LIB" && check_bash "$cmd" )
  [[ -z "$reason" ]] \
    || { echo "  expected bash '$cmd' to be silent; got reason='$reason'" >&2; exit 1; }
}

assert_file_flagged() {
  local path="$1" wt_root="${2:-}"
  local reason
  reason=$( source "$LIB" && check_file_edit "$path" "$wt_root" )
  [[ -n "$reason" ]] \
    || { echo "  expected file '$path' (wt_root='$wt_root') to be flagged" >&2; exit 1; }
}

assert_file_silent() {
  local path="$1" wt_root="${2:-}"
  local reason
  reason=$( source "$LIB" && check_file_edit "$path" "$wt_root" )
  [[ -z "$reason" ]] \
    || { echo "  expected file '$path' silent; got reason='$reason'" >&2; exit 1; }
}

assert_url_flagged() {
  local url="$1"
  local reason
  reason=$( source "$LIB" && check_web_fetch "$url" )
  [[ -n "$reason" ]] \
    || { echo "  expected URL '$url' to be flagged" >&2; exit 1; }
}

assert_url_silent() {
  local url="$1"
  local reason
  reason=$( source "$LIB" && check_web_fetch "$url" )
  [[ -z "$reason" ]] \
    || { echo "  expected URL '$url' silent; got reason='$reason'" >&2; exit 1; }
}

# --- Hook-integration helpers ---------------------------------------------

pretooluse_json() {
  local tool="$1" key="$2" value="$3"
  jq -cn --arg t "$tool" --arg k "$key" --arg v "$value" \
    '{tool_name:$t, tool_input:{($k):$v}}'
}

run_hook() {
  local envelope="$1"
  printf '%s' "$envelope" | bash "$HOOK"
}

assert_hook_asks() {
  local envelope="$1" want_substring="$2"
  local out
  out=$(run_hook "$envelope")
  local decision reason
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
  [[ "$decision" == "ask" ]] \
    || { echo "  hook did not return ask: out='$out'" >&2; exit 1; }
  [[ "$reason" == *"$want_substring"* ]] \
    || { echo "  hook reason missing '$want_substring': reason='$reason'" >&2; exit 1; }
}

assert_hook_silent() {
  local envelope="$1"
  local out
  out=$(run_hook "$envelope")
  [[ -z "$out" ]] \
    || { echo "  hook was not silent: out='$out'" >&2; exit 1; }
}
