#!/usr/bin/env bash
# SessionStart hook: inject git branch context into Claude's session.
# Stdout is added to Claude's context; stderr is shown to the user.
set -euo pipefail

# Consume the JSON input Claude Code sends to every hook
INPUT=$(cat)

# Silently exit if not inside a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

REPO=$(git rev-parse --show-toplevel)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
REMOTE_HEAD=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
MAIN_BRANCH="${REMOTE_HEAD#refs/remotes/origin/}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"

if [[ "$BRANCH" == "$MAIN_BRANCH" ]]; then
  echo "[git-workflow] ATTENTION: You are on '${MAIN_BRANCH}' in ${REPO}."
  echo "[git-workflow] Create a feature branch before making any edits:"
  echo "[git-workflow]   git checkout -b <type>/<scope>-<description>"
  echo "[git-workflow] Types: feat, fix, docs, chore, refactor"
  echo "[git-workflow] Example: git checkout -b fix/home-assistant-startup-probe"
else
  echo "[git-workflow] Active branch: ${BRANCH} (in ${REPO})"
  echo "[git-workflow] Commit each logical change atomically before moving to the next."
fi
