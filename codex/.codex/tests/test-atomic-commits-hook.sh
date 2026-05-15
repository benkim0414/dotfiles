#!/usr/bin/env bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"; HOOK="$HOOK_ROOT/atomic-commits.sh"

run_hook() {
  local cmd="$1"
  jq -cn --arg cmd "$cmd" --arg cwd "$PWD" '{
    hook_event_name: "PreToolUse",
    tool_name: "Bash",
    cwd: $cwd,
    tool_input: {
      command: $cmd
    }
  }' | bash "$HOOK"
}

assert_denied() {
  local cmd="$1"
  local output

  output="$(run_hook "$cmd")"
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"
  echo "ok denied: $cmd"
}

assert_allowed() {
  local cmd="$1"
  local output

  output="$(run_hook "$cmd")"
  if grep -q "deny" <<<"$output"; then
    echo "expected allowed but denied: $cmd" >&2
    echo "$output" >&2
    return 1
  fi
  echo "ok allowed: $cmd"
}

assert_denied "git add ."
assert_denied "git add -A"
assert_denied "git add --all"
assert_denied "git add --update"
assert_denied "git add -u"
assert_denied "git add -- ."
assert_denied "git add --verbose ."
assert_denied "git add -N ."
assert_denied "git add -p ."
assert_denied "git add -A src/app.ts"
assert_denied "git add -Av src/app.ts"
assert_denied "git add -uN src/app.ts"
assert_denied "git -C /tmp/example add ."
assert_denied "git commit -a -m 'fix(test): change'"
assert_denied "git commit -am 'fix(test): change'"
assert_denied "git commit --all -m 'fix(test): change'"
assert_denied "git commit -aS -m 'fix(test): change'"
assert_denied "git commit -S -a -m 'fix(test): change'"
assert_denied "true && git add ."
assert_denied "true; git commit -am 'fix(test): change'"
assert_denied $'echo ok\ngit add .'
assert_denied $'echo ok\ngit commit -am fix'
assert_denied "echo \"\$(git add .)\""

assert_allowed "git add src/app.ts tests/app.test.ts"
assert_allowed "git add --verbose src/app.ts"
assert_allowed "git commit -m 'fix(test): change'"
assert_allowed "git status --short"
assert_allowed "rg -n 'git add .' docs"
assert_allowed "sed -n '1,20p' README.md"
assert_allowed "echo git add ."
assert_allowed "printf 'git add .'"
assert_allowed "echo '; git add . ;'"
assert_allowed "printf '; git add . ;'"
assert_allowed 'echo "&& git commit -am fix"'
