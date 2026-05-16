#!/usr/bin/env bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
HOOK="$HOOK_ROOT/atomic-commits.sh"
TEST_ROOT=""
PRIMARY_REPO=""
LINKED_WORKTREE=""

cleanup() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    rm -rf "$TEST_ROOT"
  fi
}

trap cleanup EXIT

setup_git_fixture() {
  TEST_ROOT="$(mktemp -d)"
  PRIMARY_REPO="$TEST_ROOT/primary"
  LINKED_WORKTREE="$TEST_ROOT/linked"

  git init "$PRIMARY_REPO" >/dev/null
  git -C "$PRIMARY_REPO" config user.email "codex@example.test"
  git -C "$PRIMARY_REPO" config user.name "Codex Test"
  printf 'fixture\n' >"$PRIMARY_REPO/README.md"
  git -C "$PRIMARY_REPO" add README.md
  git -C "$PRIMARY_REPO" commit -m "test: seed fixture" >/dev/null
  git -C "$PRIMARY_REPO" worktree add "$LINKED_WORKTREE" -b fixture-worktree >/dev/null
}

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

run_hook_in_dir() {
  local cwd="$1"
  local cmd="$2"

  (
    cd "$cwd"
    jq -cn --arg cmd "$cmd" --arg cwd "$PWD" '{
      hook_event_name: "PreToolUse",
      tool_name: "Bash",
      cwd: $cwd,
      tool_input: {
        command: $cmd
      }
    }' | bash "$HOOK"
  )
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

assert_denied_in_dir() {
  local cwd="$1"
  local cmd="$2"
  local output

  output="$(run_hook_in_dir "$cwd" "$cmd")"
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"
  echo "ok denied in $cwd: $cmd"
}

assert_allowed_in_dir() {
  local cwd="$1"
  local cmd="$2"
  local output

  output="$(run_hook_in_dir "$cwd" "$cmd")"
  if [[ -n "$output" ]] && jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    echo "expected allowed in $cwd but denied: $cmd" >&2
    echo "$output" >&2
    return 1
  fi
  echo "ok allowed in $cwd: $cmd"
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

setup_git_fixture

assert_denied_in_dir "$PRIMARY_REPO" "git add ."
assert_denied_in_dir "$PRIMARY_REPO" "git add -A"
assert_denied_in_dir "$PRIMARY_REPO" "git add -u"
assert_denied_in_dir "$PRIMARY_REPO" "git commit -a -m 'fix(test): change'"
assert_denied_in_dir "$PRIMARY_REPO" "git commit -am 'fix(test): change'"
assert_allowed_in_dir "$PRIMARY_REPO" "git add README.md"
assert_allowed_in_dir "$PRIMARY_REPO" "git commit -m 'fix(test): change'"

assert_denied_in_dir "$LINKED_WORKTREE" "git add ."
assert_denied_in_dir "$LINKED_WORKTREE" "git add -A"
assert_denied_in_dir "$LINKED_WORKTREE" "git add -u"
assert_denied_in_dir "$LINKED_WORKTREE" "git commit -a -m 'fix(test): change'"
assert_denied_in_dir "$LINKED_WORKTREE" "git commit -am 'fix(test): change'"
assert_allowed_in_dir "$LINKED_WORKTREE" "git add README.md"
assert_allowed_in_dir "$LINKED_WORKTREE" "git commit -m 'fix(test): change'"
