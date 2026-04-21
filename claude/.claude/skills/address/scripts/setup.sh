#!/usr/bin/env bash

# setup.sh (pr:address)
# Fetches PR metadata, review comments, and diff, then outputs structured
# context for the pr:address skill to consume.

set -euo pipefail

# shellcheck source=../../../lib/portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../../../lib/portability.sh"

PR_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat <<'HELP'
Usage: /pr:address <pr-number-or-url>

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
  echo "Usage: /pr:address <pr-number-or-url>" >&2
  exit 1
fi

# Extract numeric PR number and optional owner/repo from various formats:
#   123, #123, URL/pull/123, URL/pulls/123, URL/pull/123/files, URL/pulls/123/changes
URL_REPO=$(echo "$PR_ARG" | grep -oE 'github\.com/[^/]+/[^/]+' | sed 's|github\.com/||' || true)
PR_NUMBER=$(echo "$PR_ARG" | grep -oE '/pulls?/[0-9]+' | grep -oE '[0-9]+' || true)
if [[ -z "$PR_NUMBER" ]]; then
  PR_NUMBER=$(echo "$PR_ARG" | tr -d '#' | grep -oE '[0-9]+$' || true)
fi
if [[ -z "$PR_NUMBER" ]]; then
  echo "Error: could not extract PR number from: $PR_ARG" >&2
  exit 1
fi

# Resolve owner/repo: prefer URL-extracted value, fall back to current repo
if [[ -n "$URL_REPO" ]]; then
  OWNER_REPO="$URL_REPO"
else
  OWNER_REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
fi

REPO_FLAG=""
if [[ -n "$URL_REPO" ]]; then
  REPO_FLAG="-R $URL_REPO"
fi

# Fetch PR metadata
# shellcheck disable=SC2086
PR_JSON=$(gh pr view "$PR_NUMBER" $REPO_FLAG --json number,title,state,author,baseRefName,headRefName,url 2>&1) || {
  echo "Error: failed to fetch PR #$PR_NUMBER: $PR_JSON" >&2
  exit 1
}

IFS=$'\t' read -r TITLE STATE BASE HEAD URL PR_AUTHOR < <(
  echo "$PR_JSON" | jq -r '[.title, .state, .baseRefName, .headRefName, .url, .author.login] | @tsv'
)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

BRANCH_MATCH=false
if [[ "$CURRENT_BRANCH" == "$HEAD" ]]; then
  BRANCH_MATCH=true
fi

# Output YAML header (quote string values to prevent YAML injection from
# titles/branches containing :, #, {, or newlines)
SAFE_TITLE=$(echo "$TITLE" | jq -Rs '.')
cat <<EOF
---
pr_number: $PR_NUMBER
owner_repo: "$OWNER_REPO"
pr_author: "$PR_AUTHOR"
pr_title: $SAFE_TITLE
head_branch: "$HEAD"
base_branch: "$BASE"
state: "$STATE"
url: "$URL"
current_branch: "$CURRENT_BRANCH"
branch_match: $BRANCH_MATCH
---
EOF

# Inline review comments (diff comments, including thread replies)
echo ""
echo "## Inline review comments"
echo ""
INLINE_ERR=$(mktemp)
if ! gh api "repos/$OWNER_REPO/pulls/$PR_NUMBER/comments" --paginate \
  --jq '.[] | {id, body, path, line, original_line, position, original_position, in_reply_to_id, user: .user.login, author_association, diff_hunk, created_at}' 2>"$INLINE_ERR"; then
  echo "ERROR: failed to fetch inline comments: $(cat "$INLINE_ERR")" >&2
  echo "(error)"
fi
rm -f "$INLINE_ERR"

# General PR comments (issue-level comments)
echo ""
echo "## General PR comments"
echo ""
GENERAL_ERR=$(mktemp)
if ! gh api "repos/$OWNER_REPO/issues/$PR_NUMBER/comments" --paginate \
  --jq '.[] | {id, body, user: .user.login, author_association, created_at}' 2>"$GENERAL_ERR"; then
  echo "ERROR: failed to fetch general comments: $(cat "$GENERAL_ERR")" >&2
  echo "(error)"
fi
rm -f "$GENERAL_ERR"

# PR reviews (top-level review objects with body text)
echo ""
echo "## PR reviews"
echo ""
REVIEW_ERR=$(mktemp)
if ! gh api "repos/$OWNER_REPO/pulls/$PR_NUMBER/reviews" --paginate \
  --jq '.[] | {id, body, state, user: .user.login, submitted_at}' 2>"$REVIEW_ERR"; then
  echo "ERROR: failed to fetch reviews: $(cat "$REVIEW_ERR")" >&2
  echo "(error)"
fi
rm -f "$REVIEW_ERR"

# Full diff for context
echo ""
echo "## Full diff"
echo ""
# shellcheck disable=SC2086
gh pr diff "$PR_NUMBER" $REPO_FLAG 2>/dev/null || echo "(no diff available)"
