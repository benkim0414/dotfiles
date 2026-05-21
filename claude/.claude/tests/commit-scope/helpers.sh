#!/usr/bin/env bash
# Sourced by every case. Provides assertions + git-fixture setup.
set -uo pipefail

: "${LIB:?LIB must be set by run.sh}"
: "${HOOK:?HOOK must be set by run.sh}"

CASE_TMP="$(mktemp -d -t commit-scope-test.XXXXXX)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# --- Lib-unit assertions ---------------------------------------------------

assert_banned() {
  local scope="$1" staged="${2:-}"
  ( source "$LIB" && is_banned_scope "$scope" "$staged" ) \
    || { echo "  expected '$scope' to be banned (staged='$staged'); was not" >&2; exit 1; }
}

assert_not_banned() {
  local scope="$1" staged="${2:-}"
  if ( source "$LIB" && is_banned_scope "$scope" "$staged" ); then
    echo "  expected '$scope' to be allowed (staged='$staged'); was banned" >&2
    exit 1
  fi
}

assert_suggest_eq() {
  local want="$1" staged="$2"
  local got
  got=$( source "$LIB" && suggest_scope "$staged" )
  [[ "$got" == "$want" ]] \
    || { echo "  suggest_scope want='$want' got='$got' (staged='$staged')" >&2; exit 1; }
}

# --- Hook-integration helpers ----------------------------------------------

# init_git_fixture <dir>
# Creates a git repo at <dir> with an initial empty commit so HEAD is valid.
init_git_fixture() {
  local dir="$1"
  ( cd "$dir" \
    && git init -q -b main \
    && git config user.email "test@example.com" \
    && git config user.name "Test" \
    && git commit -q --allow-empty -m "chore(seed): initial" )
}

# seed_known_scopes <dir> <scope1> [scope2 ...]
# Adds empty commits whose subjects use the given scopes so _known_scopes finds them.
seed_known_scopes() {
  local dir="$1"; shift
  local s
  for s in "$@"; do
    ( cd "$dir" && git commit -q --allow-empty -m "chore(${s}): seed" )
  done
}

# stage_file <dir> <path> [content]
# Touches a file in dir and stages it.
stage_file() {
  local dir="$1" path="$2" content="${3:-x}"
  mkdir -p "$(dirname "$dir/$path")"
  printf '%s\n' "$content" > "$dir/$path"
  ( cd "$dir" && git add "$path" )
}

# pretooluse_json <command>
# Emits a PreToolUse JSON envelope with command.
pretooluse_json() {
  local cmd="$1"
  jq -cn --arg c "$cmd" '{tool_input:{command:$c}}'
}

# run_hook_in <dir> <command>
# Pipes synthesized JSON to the hook, executed inside <dir>. Returns hook stdout.
run_hook_in() {
  local dir="$1" cmd="$2"
  ( cd "$dir" && pretooluse_json "$cmd" | bash "$HOOK" )
}

assert_hook_emits() {
  local out="$1" needle="$2"
  echo "$out" | grep -qF -- "$needle" \
    || { echo "  hook output missing '$needle'; got: $out" >&2; exit 1; }
}

assert_hook_silent_on() {
  local out="$1" needle="$2"
  if echo "$out" | grep -qF -- "$needle"; then
    echo "  hook unexpectedly emitted '$needle'; got: $out" >&2; exit 1
  fi
}
