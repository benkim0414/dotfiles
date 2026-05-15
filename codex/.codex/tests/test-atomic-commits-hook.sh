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
  if [[ -n "$output" ]] && jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
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
assert_denied "git add --pathspec-from-file=-"
assert_denied "git add --pathspec-from-file=paths.txt"
assert_denied "git add --pathspec-from-file paths.txt"
assert_denied "git add --pathspec-file-nul --pathspec-from-file=-"
assert_denied "git add -u"
assert_denied "git add -- ."
assert_denied "git add ./"
assert_denied "git add :/"
assert_denied "git add :"
assert_denied "git add ':(top)'"
assert_denied "git add ':!README.md'"
assert_denied "git add ':^README.md'"
assert_denied "git add ':(exclude)README.md'"
assert_denied "git add ':(exclude,top)README.md'"
assert_denied "git add *"
assert_denied "git add src/*.ts"
assert_denied "git add src/file?.ts"
assert_denied "git add src/[ab].ts"
assert_denied "git add --verbose ."
assert_denied "git add -N ."
assert_denied "git add -p ."
assert_denied "git add -A src/app.ts"
assert_denied "git add -Av src/app.ts"
assert_denied "git add -uN src/app.ts"
assert_denied 'git add "."'
assert_denied 'git add "./"'
assert_denied 'git add "--all"'
assert_denied "git -C /tmp/example add ."
assert_denied "git -c core.autocrlf=false add ."
assert_denied "git --work-tree=/tmp add ."
assert_denied "git -C /tmp -c core.autocrlf=false add ."
assert_denied "( git add . )"
assert_denied "command git add ."
assert_denied "time git add ."
assert_denied "if true; then git add .; fi"
assert_denied "if true; then command git add .; fi"
assert_denied "for x in 1; do command git add .; done"
assert_denied "time command git add ."
assert_denied "while true; do time git add .; done"
assert_denied "env git add ."
assert_denied "env GIT_DIR=.git git add ."
assert_denied "sudo git add ."
assert_denied "exec git add ."
assert_denied "bash -lc 'git add .'"
assert_denied "sh -c 'git commit -am fix'"
assert_denied "zsh -c 'git add .'"
assert_denied "env bash -lc 'git commit -am fix'"
assert_denied "sudo sh -c 'git add .'"
assert_denied "exec sh -c 'git add .'"
assert_denied "printf './\n' | git add --pathspec-from-file=-"
assert_denied "git commit -a -m 'fix(test): change'"
assert_denied "git commit -am 'fix(test): change'"
assert_denied "git commit --all -m 'fix(test): change'"
assert_denied "git commit -aS -m 'fix(test): change'"
assert_denied "git commit -S -a -m 'fix(test): change'"
assert_denied 'git commit "--all" -m fix'
assert_denied 'git commit "-am" fix'
assert_denied "git -c core.autocrlf=false commit -am fix"
assert_denied "( git commit -am fix )"
assert_denied "command git commit -am fix"
assert_denied "time git commit -am fix"
assert_denied "if true; then git commit -am fix; fi"
assert_denied "if true; then command git commit -am fix; fi"
assert_denied "for x in 1; do command git commit -am fix; done"
assert_denied "time command git commit -am fix"
assert_denied "while true; do time git commit -am fix; done"
assert_denied "env git commit -am fix"
assert_denied "sudo git commit -am fix"
assert_denied "exec git commit -am fix"
assert_denied "bash -lc 'git commit -am fix'"
assert_denied "env sh -c 'git add .'"
assert_denied "sudo bash -lc 'git commit -am fix'"
assert_denied "true && git add ."
assert_denied "true; git commit -am 'fix(test): change'"
assert_denied "printf ok | git add ."
assert_denied "printf ok | git commit -am fix"
assert_denied "printf ok |& git add ."
assert_denied "printf ok |& git commit -am fix"
assert_denied "sleep 1 & git add ."
assert_denied "sleep 1 & git commit -am fix"
assert_denied $'echo ok\ngit add .'
assert_denied $'echo ok\ngit commit -am fix'
assert_denied "echo \"\$(git add .)\""
assert_denied "echo \`git add .\`"
assert_denied "echo \"\`git add .\`\""

assert_allowed "git add src/app.ts tests/app.test.ts"
assert_allowed "git add --verbose src/app.ts"
assert_allowed "git add src/app.ts src/app.test.ts"
assert_allowed "git commit -m 'fix(test): change'"
assert_allowed 'git commit -m "-am"'
assert_allowed 'git commit -m "--all"'
assert_allowed 'git commit --message "-a"'
assert_allowed 'git commit --message=-a'
assert_allowed "git status --short"
assert_allowed "rg -n 'git add .' docs"
assert_allowed "sed -n '1,20p' README.md"
assert_allowed "echo git add ."
assert_allowed "printf 'git add .'"
assert_allowed "echo '; git add . ;'"
assert_allowed "printf '; git add . ;'"
assert_allowed 'echo "&& git commit -am fix"'
assert_allowed 'echo "x\"; git add ."'
