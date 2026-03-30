#!/bin/bash

# setup-review-cl.sh
# Creates a ralph-loop state file with a baked-in pre-PR code review prompt.
# The ralph-loop Stop hook (from the ralph-loop plugin) handles iteration.

set -euo pipefail

MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations requires a non-negative integer" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'HELP'
Usage: /review-cl [--max-iterations N]

Review all worktree changes iteratively, fix issues, then create a PR.
Uses Ralph Loop to iterate until the review is clean.

Options:
  --max-iterations N   Maximum review iterations (default: 10)
  -h, --help           Show this help message
HELP
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      echo "Usage: /review-cl [--max-iterations N]" >&2
      exit 1
      ;;
  esac
done

# Guard: must be in a worktree (not on main)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || true)
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  echo "Error: /review-cl must be run from a worktree branch, not $CURRENT_BRANCH" >&2
  echo "Call EnterWorktree() first to create an isolated branch." >&2
  exit 1
fi

# Guard: abort if a Ralph Loop is already active
if [[ -f .claude/ralph-loop.local.md ]]; then
  EXISTING_ITER=$(sed -n 's/^iteration: *//p' .claude/ralph-loop.local.md)
  echo "Error: a Ralph Loop is already active (iteration ${EXISTING_ITER:-?})" >&2
  echo "Run /cancel-ralph first, then retry." >&2
  exit 1
fi

mkdir -p .claude

cat > .claude/ralph-loop.local.md <<STATEEOF
---
active: true
iteration: 1
session_id: "${CLAUDE_CODE_SESSION_ID:-}"
max_iterations: $MAX_ITERATIONS
completion_promise: "PR_CREATED"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

## Pre-PR Code Review

You are iteratively reviewing all changes in this worktree before creating a PR.
Each iteration, review the full diff against main, fix any issues, and verify.

### Gather Changes
1. Run \`git log --oneline \$(git merge-base HEAD main)..HEAD\` to list all commits
2. Run \`git diff \$(git merge-base HEAD main)..HEAD\` to see the full diff
3. Run \`git status\` to check for uncommitted changes
4. If uncommitted changes exist, stage and commit them first

### Review Criteria
For every changed file in the diff, check:
- **Correctness**: bugs, logic errors, off-by-one, edge cases
- **Security**: hardcoded secrets, injection, missing input validation at boundaries
- **Quality**: dead code, unreachable branches, unnecessary complexity
- **Conventions**: adherence to CLAUDE.md and project-level conventions
- **Shell scripts**: ShellCheck compliance (no warnings)

### If Issues Found
For each issue:
1. Fix the issue
2. \`git add <specific-files>\` (never \`git add -A\` or \`git add .\`)
3. \`git commit\` with conventional commit format
4. Continue reviewing -- do NOT output the completion promise yet

### If Review Is Clean
When the full diff has been reviewed and no issues remain:
1. Push the branch: \`git push origin HEAD:\$(git branch --show-current)\`
2. Create a PR with \`gh pr create\` including a summary and test plan
3. Output: <promise>PR_CREATED</promise>

Only output the promise when the PR has been successfully created.
STATEEOF

cat <<EOF
Review loop activated.

Iterations: 1 / $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
Completion promise: PR_CREATED (only when review is clean and PR is created)

The Ralph Loop stop hook will iterate the review until clean.
To cancel: /cancel-ralph
EOF
