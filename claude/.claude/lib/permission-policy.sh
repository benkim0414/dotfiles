#!/usr/bin/env bash
# Permission-policy lib for the PreToolUse permission-policy.sh hook.
# Source this file; do not execute it directly.
#
# Public API:
#   check_bash <command>                 -- emit reason or empty
#   check_file_edit <path> <wt_root>     -- emit reason or empty
#   check_web_fetch <url>                -- emit reason or empty
#   canonical_path <path>                -- echo canonical path (no symlinks)

# --- canonical_path -------------------------------------------------------
# Resolve symlinks and "." / ".." segments to an absolute path.
# Uses GNU readlink -f if available, falls back to python3 realpath.
canonical_path() {
  local p="$1"
  if readlink -f / >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null && return 0
  fi
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' -- "$p" 2>/dev/null
}

# --- check_bash -----------------------------------------------------------
# Inspect a bash command string and return a non-empty reason if any
# risky-shape pattern matches; empty otherwise.
check_bash() {
  local cmd="$1"
  # Shell-expanded secret paths the tilde-prefix deny list misses.
  if [[ "$cmd" == *'$HOME/.ssh/'* \
     || "$cmd" == *'${HOME}/.ssh/'* \
     || "$cmd" == *'/Users/ben/.ssh/'* \
     || "$cmd" == *'$HOME/.aws/credentials'* \
     || "$cmd" == *'${HOME}/.aws/credentials'* \
     || "$cmd" == *'/Users/ben/.aws/credentials'* \
     || "$cmd" == *'$HOME/.claude/.credentials'* \
     || "$cmd" == *'${HOME}/.claude/.credentials'* \
     || "$cmd" == *'/Users/ben/.claude/.credentials'* \
     || "$cmd" == *'$HOME/.gnupg/'* \
     || "$cmd" == *'${HOME}/.gnupg/'* \
     || "$cmd" == *'/Users/ben/.gnupg/'* ]]; then
    printf 'Bash command references secret path via non-tilde form'
    return 0
  fi
  # Bypass attempts for `rm -rf` that evade the deny/ask pattern.
  # Detect leading whitespace AND prefixed command forms directly against $cmd.
  if [[ "$cmd" =~ ^[[:space:]]+rm[[:space:]]+-r[fF]?[[:space:]] \
     || "$cmd" =~ ^\\rm[[:space:]]+-r[fF]?[[:space:]] \
     || "$cmd" =~ ^command[[:space:]]+rm[[:space:]]+-r[fF]?[[:space:]] \
     || "$cmd" =~ ^builtin[[:space:]]+rm[[:space:]]+-r[fF]?[[:space:]] \
     || "$cmd" =~ ^\"rm\"[[:space:]]+-r[fF]?[[:space:]] \
     || "$cmd" =~ ^\'rm\'[[:space:]]+-r[fF]?[[:space:]] ]]; then
    printf 'Possible deny-list bypass for rm -rf'
    return 0
  fi
  printf ''
}

# --- check_file_edit ------------------------------------------------------
# Inspect a file_path (canonicalized internally) plus the worktree root and
# return a non-empty reason if the edit targets safety-critical claude config
# outside the current worktree, or persistence/shell-init files.
check_file_edit() {
  local path="$1" wt_root="${2:-}"
  # Implemented in later tasks.
  printf ''
}

# --- check_web_fetch ------------------------------------------------------
# Inspect a URL string and return a non-empty reason if it matches exfil /
# suspect-host / local-path patterns.
check_web_fetch() {
  local url="$1"
  # Implemented in later tasks.
  printf ''
}
