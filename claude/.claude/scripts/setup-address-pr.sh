#!/usr/bin/env bash

# setup-address-pr.sh
# Fetches PR metadata, review comments, and diff, then outputs structured
# context for the address-pr skill to consume.

set -euo pipefail

# shellcheck source=../lib/portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/portability.sh"

PR_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat <<'HELP'
Usage: /address-pr <pr-number-or-url>

Address all review comments in a PR: make code changes, commit atomically,
push, and reply to each comment.

Options:
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
  echo "Usage: /address-pr <pr-number-or-url>" >&2
  exit 1
fi

# Extract numeric PR number from various formats:
#   123, #123, URL/pull/123, URL/pulls/123, URL/pull/123/files, URL/pulls/123/changes
PR_NUMBER=$(echo "$PR_ARG" | grep -oE '/pulls?/[0-9]+' | grep -oE '[0-9]+' || true)
if [[ -z "$PR_NUMBER" ]]; then
  PR_NUMBER=$(echo "$PR_ARG" | tr -d '#' | grep -oE '[0-9]+$' || true)
fi
if [[ -z "$PR_NUMBER" ]]; then
  echo "Error: could not extract PR number from: $PR_ARG" >&2
  exit 1
fi

# Fetch PR metadata
PR_JSON=$(gh pr view "$PR_NUMBER" --json number,title,state,author,baseRefName,headRefName,url 2>&1) || {
  echo "Error: failed to fetch PR #$PR_NUMBER: $PR_JSON" >&2
  exit 1
}

IFS=$'\t' read -r TITLE STATE BASE HEAD URL PR_AUTHOR < <(
  echo "$PR_JSON" | jq -r '[.title, .state, .baseRefName, .headRefName, .url, .author.login] | @tsv'
)

OWNER_REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

BRANCH_MATCH=false
if [[ "$CURRENT_BRANCH" == "$HEAD" ]]; then
  BRANCH_MATCH=true
fi

# Output YAML header
cat <<EOF
---
pr_number: $PR_NUMBER
owner_repo: $OWNER_REPO
pr_author: $PR_AUTHOR
pr_title: $TITLE
head_branch: $HEAD
base_branch: $BASE
state: $STATE
url: $URL
current_branch: $CURRENT_BRANCH
branch_match: $BRANCH_MATCH
---
EOF

# Inline review comments (diff comments, including thread replies)
echo ""
echo "## Inline review comments"
echo ""
gh api "repos/$OWNER_REPO/pulls/$PR_NUMBER/comments?per_page=100" --paginate \
  --jq '.[] | {id, body, path, line, original_line, position, original_position, in_reply_to_id, user: .user.login, author_association, diff_hunk, created_at}' 2>/dev/null || echo "(none)"

# General PR comments (issue-level comments)
echo ""
echo "## General PR comments"
echo ""
gh api "repos/$OWNER_REPO/issues/$PR_NUMBER/comments?per_page=100" --paginate \
  --jq '.[] | {id, body, user: .user.login, author_association, created_at}' 2>/dev/null || echo "(none)"

# PR reviews (top-level review objects with body text)
echo ""
echo "## PR reviews"
echo ""
gh api "repos/$OWNER_REPO/pulls/$PR_NUMBER/reviews" --paginate \
  --jq '.[] | {id, body, state, user: .user.login, submitted_at}' 2>/dev/null || echo "(none)"

# Full diff for context
echo ""
echo "## Full diff"
echo ""
gh pr diff "$PR_NUMBER" 2>/dev/null || echo "(no diff available)"
