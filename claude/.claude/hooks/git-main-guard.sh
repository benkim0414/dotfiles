#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): block git commit/push on the main branch.
# Exit 0 = allow. Exit 2 = block (stderr is fed back to Claude).
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only guard git commit and git push; all other Bash calls pass through immediately
if [[ ! "$COMMAND" =~ ^git[[:space:]]+(commit|push) ]]; then
  exit 0
fi

# Silently allow if not inside a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
REMOTE_HEAD=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
MAIN_BRANCH="${REMOTE_HEAD#refs/remotes/origin/}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"

if [[ "$BRANCH" == "$MAIN_BRANCH" ]]; then
  echo "BLOCKED: Cannot commit/push directly on '${MAIN_BRANCH}'." >&2
  echo "Create a feature branch first:" >&2
  echo "  git checkout -b <type>/<scope>-<description>" >&2
  exit 2
fi
