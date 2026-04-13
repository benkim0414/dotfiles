#!/usr/bin/env bash

# setup-review-pr.sh
# Creates a temp worktree, launches Codex and Copilot reviews in the background,
# and outputs structured context for the review-pr skill to consume.

set -euo pipefail

# shellcheck source=../lib/portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/portability.sh"

POST=false
PR_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --post)
      POST=true
      shift
      ;;
    -h|--help)
      cat <<'HELP'
Usage: /review-pr <pr-number-or-url> [--post]

Review a PR with multiple AI reviewers (Claude Code, Codex, Copilot).

Options:
  --post    Post the review as a GitHub PR review comment
  -h, --help  Show this help message
HELP
      exit 0
      ;;
    *)
      PR_ARG="$1"
      shift
      ;;
  esac
done

if [[ -z "$PR_ARG" ]]; then
  echo "Error: no PR number or URL provided" >&2
  echo "Usage: /review-pr <pr-number-or-url> [--post]" >&2
  exit 1
fi

# Extract numeric PR number from various formats (123, #123, URL/pull/123)
PR_NUMBER=$(echo "$PR_ARG" | grep -oE '[0-9]+$' || true)
if [[ -z "$PR_NUMBER" ]]; then
  echo "Error: could not extract PR number from: $PR_ARG" >&2
  exit 1
fi

# Fetch PR metadata
PR_JSON=$(gh pr view "$PR_NUMBER" --json number,title,state,baseRefName,headRefName 2>&1) || {
  echo "Error: failed to fetch PR #$PR_NUMBER: $PR_JSON" >&2
  exit 1
}

IFS=$'\t' read -r TITLE BASE HEAD STATE < <(
  echo "$PR_JSON" | jq -r '[.title, .baseRefName, .headRefName, .state] | @tsv'
)

if [[ "$STATE" != "OPEN" ]]; then
  echo "Error: PR #$PR_NUMBER is $STATE, not OPEN" >&2
  exit 1
fi

# Fetch the remote branch for the worktree
git fetch origin "$HEAD" --no-tags --quiet 2>/dev/null || true

WORKTREE="/tmp/review-pr-${PR_NUMBER}"
CODEX_OUT="/tmp/review-pr-${PR_NUMBER}.codex.md"
COPILOT_OUT="/tmp/review-pr-${PR_NUMBER}.copilot.md"

# Clean stale worktree if it exists
if [[ -d "$WORKTREE" ]]; then
  git worktree remove "$WORKTREE" --force 2>/dev/null || true
  git worktree prune 2>/dev/null || true
fi

# Clean stale output files
rm -f "$CODEX_OUT" "$COPILOT_OUT"

# Create detached worktree
if git worktree add "$WORKTREE" "origin/$HEAD" --detach --quiet 2>/dev/null; then
  WORKTREE_OK=true
else
  WORKTREE_OK=false
  echo "Warning: failed to create worktree, Codex review will be skipped" >&2
fi

# Launch Codex review in background
CODEX_PID=none
if [[ "$WORKTREE_OK" == "true" ]] && command -v codex &>/dev/null; then
  (cd "$WORKTREE" && codex review --base "$BASE" --title "$TITLE" > "$CODEX_OUT" 2>&1) &
  CODEX_PID=$!
fi

# Launch Copilot review in background
COPILOT_PID=none
if gh copilot --version &>/dev/null 2>&1; then
  (gh pr diff "$PR_NUMBER" 2>/dev/null | gh copilot -p \
    "Review this pull request diff for bugs, security issues, and improvements. Be specific about file paths and line numbers. Format findings as: **[severity]** \`file:line\` -- description" \
    > "$COPILOT_OUT" 2>&1) &
  COPILOT_PID=$!
fi

# Output structured context for the skill
cat <<EOF
---
pr_number: $PR_NUMBER
post: $POST
worktree: $WORKTREE
codex_pid: $CODEX_PID
codex_output: $CODEX_OUT
copilot_pid: $COPILOT_PID
copilot_output: $COPILOT_OUT
---
Background reviewers launched. Codex PID: $CODEX_PID. Copilot PID: $COPILOT_PID.
EOF
