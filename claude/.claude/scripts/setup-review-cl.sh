#!/usr/bin/env bash

# setup-review-cl.sh
# Creates a ralph-loop state file with a baked-in pre-PR code review prompt.
# The ralph-loop Stop hook (from the ralph-loop plugin) handles iteration.

set -euo pipefail

# shellcheck source=../lib/portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/portability.sh"

MAX_ITERATIONS=10
FORCE=false

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
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      cat <<'HELP'
Usage: /review-cl [--max-iterations N] [--force]

Review all worktree changes iteratively, fix issues, then create a PR.
Uses Ralph Loop to iterate until the review is clean.

Options:
  --max-iterations N   Maximum review iterations (default: 10)
  --force              Remove any existing state file and start fresh
  -h, --help           Show this help message
HELP
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      echo "Usage: /review-cl [--max-iterations N] [--force]" >&2
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

# Guard: check for existing Ralph Loop state file
STATE_FILE=.claude/ralph-loop.local.md
if [[ -f "$STATE_FILE" ]]; then
  if [[ "$FORCE" == "true" ]]; then
    echo "Warning: removing existing state file (--force)" >&2
    rm -f "$STATE_FILE"
  else
    STORED_ACTIVE=$(sed -n 's/^active: *//p' "$STATE_FILE")
    STORED_SESSION=$(sed -n 's/^session_id: *"\(.*\)"/\1/p' "$STATE_FILE")
    STORED_STARTED=$(sed -n 's/^started_at: *"\(.*\)"/\1/p' "$STATE_FILE")
    EXISTING_ITER=$(sed -n 's/^iteration: *//p' "$STATE_FILE")
    CURRENT_SESSION="${CLAUDE_CODE_SESSION_ID:-}"

    STALE=false

    # Signal 1: loop marked inactive
    if [[ "$STORED_ACTIVE" != "true" ]]; then
      STALE=true
    # Signal 2: current session known and differs from stored
    elif [[ -n "$CURRENT_SESSION" && "$CURRENT_SESSION" != "$STORED_SESSION" ]]; then
      STALE=true
    # Signal 3: both session IDs empty -- fall back to age check
    elif [[ -z "$CURRENT_SESSION" && -z "$STORED_SESSION" && -n "$STORED_STARTED" ]]; then
      STARTED_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STORED_STARTED" +%s 2>/dev/null \
                      || date -d "$STORED_STARTED" +%s 2>/dev/null \
                      || echo 0)
      AGE_HOURS=$(( (EPOCHSECONDS - STARTED_EPOCH) / 3600 ))
      if (( AGE_HOURS >= 6 )); then
        STALE=true
      fi
    fi

    if [[ "$STALE" == "true" ]]; then
      echo "Note: cleaning up stale Ralph Loop state (iteration ${EXISTING_ITER:-?})." >&2
      rm -f "$STATE_FILE"
    else
      echo "Error: a Ralph Loop is already active (iteration ${EXISTING_ITER:-?})" >&2
      echo "Run /cancel-ralph first, or use --force to override." >&2
      exit 1
    fi
  fi
fi

mkdir -p .claude

cat > "$STATE_FILE" <<STATEEOF
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
3. Clean up the loop state file: \`rm -f .claude/ralph-loop.local.md\`
4. Output: <promise>PR_CREATED</promise>

Only output the promise when the PR has been successfully created.
The state file MUST be removed before outputting the promise.
STATEEOF

cat <<EOF
Review loop activated.

Iterations: 1 / $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
Completion promise: PR_CREATED (only when review is clean and PR is created)

The Ralph Loop stop hook will iterate the review until clean.
To cancel: /cancel-ralph
EOF
