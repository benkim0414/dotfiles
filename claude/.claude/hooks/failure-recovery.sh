#!/usr/bin/env bash
# PostToolUseFailure hook: inject targeted recovery guidance when tools fail.
# Pattern-matches common failure modes and provides specific remediation steps.
# Fast exit for unrecognized failures.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)

# --- Extract tool name and error output without jq for the fast path ---
if [[ "$INPUT" != *'"tool_name"'* ]]; then
  exit 0
fi

IFS=$'\t' read -r TOOL_NAME TOOL_ERROR <<< "$(
  printf '%s' "$INPUT" | jq -r '[
    (.tool_name // ""),
    ((.tool_error // .tool_output // "") | tostring | .[0:2000])
  ] | @tsv' 2>/dev/null || true
)"

[[ -z "$TOOL_NAME" ]] && exit 0
[[ -z "$TOOL_ERROR" ]] && exit 0

# Convert to lowercase for matching.
error_lower="${TOOL_ERROR,,}"
guidance=""

# --- Pattern: deleted CWD / path does not exist ---
if [[ "$error_lower" == *"path"*"does not exist"* ]] ||
   [[ "$error_lower" == *"no such file or directory"* && "$TOOL_NAME" == "Bash" ]]; then
  repo_hint=""
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    repo_hint="${BASH_REMATCH[1]}"
  fi
  if [[ -n "$repo_hint" ]]; then
    guidance="The working directory no longer exists (likely a deleted worktree). The user must type at the Claude Code prompt: ! cd \"${repo_hint}\" -- then retry."
  else
    guidance="The working directory or target path does not exist. If stuck in a deleted worktree, the user must type: ! cd <project-root> at the Claude Code prompt."
  fi
fi

# --- Pattern: GitHub CLI authentication ---
if [[ -z "$guidance" ]] && [[ "$TOOL_NAME" == "Bash" ]]; then
  if [[ "$error_lower" == *"gh auth"* ]] ||
     [[ "$error_lower" == *"authentication"*"required"* ]] ||
     [[ "$error_lower" == *"not logged"* ]]; then
    guidance="GitHub CLI authentication issue. The user should run: ! gh auth status -- to check auth, then: ! gh auth login -- if needed."
  fi
fi

# --- Pattern: git merge conflicts ---
if [[ -z "$guidance" ]] && [[ "$TOOL_NAME" == "Bash" ]]; then
  if [[ "$error_lower" == *"conflict"* && "$error_lower" == *"merge"* ]] ||
     [[ "$error_lower" == *"unmerged"* ]] ||
     [[ "$error_lower" == *"fix conflicts"* ]]; then
    guidance="Git merge conflict detected. Resolve conflicts in the affected files, then stage and commit. Use 'git diff' to see conflict markers and 'git status' to list unmerged files."
  fi
fi

# --- Pattern: permission denied on file operations ---
if [[ -z "$guidance" ]] && [[ "$TOOL_NAME" =~ ^(Write|Edit|MultiEdit)$ ]]; then
  if [[ "$error_lower" == *"permission denied"* ]] ||
     [[ "$error_lower" == *"read-only"* ]]; then
    guidance="File permission denied. Check: (1) worktree state -- is EnterWorktree() needed? (2) file ownership -- is this a system file? (3) read-only filesystem."
  fi
fi

# --- Pattern: command timeout ---
if [[ -z "$guidance" ]]; then
  if [[ "$error_lower" == *"timed out"* ]] ||
     [[ "$error_lower" == *"timeout"* ]]; then
    guidance="Command timed out. Consider: (1) breaking the operation into smaller steps, (2) running with a longer timeout, (3) checking if a background process is blocking."
  fi
fi

# No recognized pattern — exit silently.
[[ -z "$guidance" ]] && exit 0

emit_context "PostToolUseFailure" "$guidance"
