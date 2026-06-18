#!/usr/bin/env bash
# Verifies the atlassian/slack auto-allow-except-destructive policy.
# Merges settings.base.json + settings.overlay.json with the same jq
# semantics as claude-sync, then resolves representative MCP tools through
# Claude Code's deny -> ask -> allow precedence (first match wins).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HERE/../.."
BASE="$CLAUDE_DIR/settings.base.json"
OVERLAY="$CLAUDE_DIR/settings.overlay.json"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }
[[ -f "$BASE" ]]    || { echo "missing $BASE" >&2; exit 2; }
[[ -f "$OVERLAY" ]] || { echo "missing $OVERLAY" >&2; exit 2; }

jq empty "$BASE"    || { echo "base is not valid JSON" >&2; exit 1; }
jq empty "$OVERLAY" || { echo "overlay is not valid JSON" >&2; exit 1; }

MERGED="$(jq -n --slurpfile base "$BASE" --slurpfile over "$OVERLAY" '
  def merge(b):
    if (type == "array") and (b | type == "array") then
      if all(type == "string") and (b | all(type == "string"))
      then reduce (. + b)[] as $x ([]; if index($x) then . else . + [$x] end)
      else . + b end
    elif (type == "object") and (b | type == "object") then
      reduce (b | to_entries[]) as $e (.;
        if has($e.key) then .[$e.key] |= merge($e.value)
        else . + {($e.key): $e.value} end)
    else b end;
  $base[0] | merge($over[0])
')" || { echo "merge failed" >&2; exit 1; }

DENY=();  while IFS= read -r l; do DENY+=("$l");  done < <(jq -r '.permissions.deny[]?'  <<<"$MERGED")
ASK=();   while IFS= read -r l; do ASK+=("$l");   done < <(jq -r '.permissions.ask[]?'   <<<"$MERGED")
ALLOW=(); while IFS= read -r l; do ALLOW+=("$l"); done < <(jq -r '.permissions.allow[]?' <<<"$MERGED")

anymatch() { local tool="$1"; shift; (( $# == 0 )) && return 1; local p; for p in "$@"; do [[ "$tool" == $p ]] && return 0; done; return 1; }

classify() {
  local tool="$1"
  anymatch "$tool" "${DENY[@]}"  && { echo deny;  return; }
  anymatch "$tool" "${ASK[@]}"   && { echo ask;   return; }
  anymatch "$tool" "${ALLOW[@]}" && { echo allow; return; }
  echo classifier
}

fail=0
expect() {
  local tool="$1" want="$2" got
  got="$(classify "$tool")"
  if [[ "$got" == "$want" ]]; then
    printf '  ok   %-52s -> %s\n' "$tool" "$got"
  else
    printf '  FAIL %-52s -> %s (want %s)\n' "$tool" "$got" "$want"; fail=1
  fi
}

# Bucket A (reads) + Bucket B (non-destructive writes) -> allow
expect mcp__atlassian__jira_get_issue              allow
expect mcp__atlassian__jira_search                 allow
expect mcp__atlassian__jira_create_issue           allow
expect mcp__atlassian__jira_update_issue           allow
expect mcp__atlassian__jira_add_comment            allow
expect mcp__atlassian__jira_transition_issue       allow
expect mcp__atlassian__confluence_create_page      allow
expect mcp__atlassian__confluence_update_page      allow
expect mcp__slack__slack_post_message              allow
expect mcp__slack__slack_reply_to_thread           allow
expect mcp__slack__slack_add_reaction              allow

# Bucket C (destructive) -> ask
expect mcp__atlassian__jira_delete_issue            ask
expect mcp__atlassian__jira_remove_issue_link       ask
expect mcp__atlassian__jira_remove_watcher          ask
expect mcp__atlassian__confluence_delete_page       ask
expect mcp__atlassian__confluence_delete_attachment ask

echo
if [[ $fail -eq 0 ]]; then echo "mcp-permission-overlay: all passed"; else echo "mcp-permission-overlay: FAILURES"; fi
exit $fail
