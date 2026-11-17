#!/usr/bin/env bash
# git-stage-guard hook test.
#
# Feeds PreToolUse JSON for a Bash call to the hook and checks its verdict.
# The hook blocks with exit 2; it allows with exit 0. Any other status is a
# failure here, so a crash never reads as "allowed".
#
# Exits 0 if all pass, 1 on any failure, 2 when a prerequisite is missing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../../hooks/git-stage-guard.py"

command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 2; }
[[ -x "$HOOK" ]] || { echo "missing or not executable: $HOOK" >&2; exit 2; }

fail=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# run <command> -> sets status and err
run() {
  local json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1")
  err=$(printf '%s' "$json" | "$HOOK" 2>&1 >/dev/null)
  status=$?
}

expect_block() {
  run "$1"
  if [[ $status -eq 2 && -n "$err" ]]; then ok "blocks: $1"
  else bad "blocks: $1 (status $status)"; fi
}

expect_allow() {
  run "$1"
  if [[ $status -eq 0 ]]; then ok "allows: $1"
  else bad "allows: $1 (status $status: $err)"; fi
}

echo "git add: broad forms"
expect_block 'git add -A'
expect_block 'git add --all'
expect_block 'git add .'
expect_block 'git add ./'
expect_block 'git add -- .'
expect_block 'git add -u'
expect_block 'git add --update'
expect_block 'git add --no-ignore-removal'
expect_block 'git add -vA'
expect_block 'git add -A src/'

echo "git commit: -a forms"
expect_block 'git commit -a -m "msg"'
expect_block 'git commit -am "msg"'
expect_block 'git commit -va'
expect_block 'git commit --all -m msg'

echo "wrapped and chained"
expect_block 'git -C /tmp/repo add -A'
expect_block 'git -c core.x=y add .'
expect_block 'GIT_DIR=x git add -A'
expect_block 'rtk git add -A'
expect_block 'cd repo && git add .'
expect_block 'git status; git add -A'
expect_block $'git status\ngit add -A'

echo "allowed"
expect_allow 'git add claude/.claude/CLAUDE.md'
expect_allow 'git add .claude/settings.json'
expect_allow 'git add ./src/main.py'
expect_allow 'git add -p src/'
expect_allow 'git commit -m "add -A support"'
expect_allow 'git commit -m "-a is banned"'
expect_allow 'git commit -ma'
expect_allow 'git commit -F msg.txt'
expect_allow $'git commit -q -F - <<\'EOF\'\nfeat: x\nEOF'
expect_allow 'git status'
expect_allow 'echo "git add -A"'
expect_allow 'ls -A'

echo "input it cannot parse is allowed, not crashed"
expect_allow 'git commit -m "unterminated'
err=$(printf '%s' '{not json' | "$HOOK" 2>&1 >/dev/null); json_status=$?
if [[ $json_status -eq 0 ]]; then ok "allows: malformed JSON input"
else bad "allows: malformed JSON input (status $json_status)"; fi

if [[ $fail -eq 0 ]]; then echo "all passed"; fi
exit $fail
