#!/usr/bin/env bash

# setup-create-pr.sh
# Creates a ralph-loop state file with a multi-pass review prompt.
# Delegates review to pluggable skills (/simplify, /review, /codex:review)
# then falls back to a manual self-check before creating the PR.

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
Usage: /create-pr [--max-iterations N] [--force]

Multi-pass review of all worktree changes, then create a PR.
Uses Ralph Loop to iterate until every review pass is clean.

Review passes (in order):
  1. /simplify     -- code quality, reuse, efficiency (auto-fixes)
  2. /review       -- general review (skipped if unavailable)
  3. /codex:review -- codex review (skipped if unavailable)
  4. Self-check    -- security, conventions, ShellCheck

Options:
  --max-iterations N   Maximum review iterations (default: 10)
  --force              Remove any existing state file and start fresh
  -h, --help           Show this help message
HELP
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      echo "Usage: /create-pr [--max-iterations N] [--force]" >&2
      exit 1
      ;;
  esac
done

# Guard: must be in a worktree (not on main)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || true)
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  echo "Error: /create-pr must be run from a worktree branch, not $CURRENT_BRANCH" >&2
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
    # Signal 3: current session unknown -- fall back to age check
    elif [[ -z "$CURRENT_SESSION" && -n "$STORED_STARTED" ]]; then
      STARTED_EPOCH=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STORED_STARTED" +%s 2>/dev/null \
                      || date -u -d "$STORED_STARTED" +%s 2>/dev/null \
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

## Pre-PR Review & Create

You are iteratively reviewing all worktree changes before creating a PR.
Each iteration runs multiple review passes, fixes issues, then re-checks.

### Phase 1: Gather Changes
1. Run \`git log --oneline \$(git merge-base HEAD main)..HEAD\` to list all commits
2. Run \`git diff \$(git merge-base HEAD main)..HEAD\` to see the full diff
3. Run \`git status\` to check for uncommitted changes
4. If uncommitted changes exist, stage and commit them first

### Phase 2: Run Review Skills

Run each review skill via the Skill tool. Each pass targets a different
dimension of quality. If a skill is not available, skip it gracefully.

**Pass 1 -- /simplify** (code quality, reuse, efficiency)
- Invoke: use the Skill tool with skill "simplify"
- This skill auto-fixes issues it finds.
- After it completes, if files were changed, \`git add <specific-files>\`
  (never \`git add -A\` or \`git add .\`) and \`git commit\` with a conventional message.

**Pass 2 -- /review** (general review)
- Invoke: use the Skill tool with skill "review"
- If the skill is unavailable (error), log "Pass 2 skipped: /review not available" and continue.
- If it reports issues, fix them, then \`git add <specific-files>\` and \`git commit\`.

**Pass 3 -- /codex:review** (codex review)
- Invoke: use the Skill tool with skill "codex:review"
- If the skill is unavailable (error), log "Pass 3 skipped: /codex:review not available" and continue.
- If it reports issues, fix them, then \`git add <specific-files>\` and \`git commit\`.

### Phase 3: Self-check

After all skill passes, do a final manual review of the full diff:
- **Correctness**: bugs, logic errors, off-by-one, edge cases
- **Security**: hardcoded secrets, injection, missing input validation at boundaries
- **Quality**: dead code, unreachable branches, unnecessary complexity
- **Conventions**: adherence to CLAUDE.md and project-level conventions
- **Shell scripts**: ShellCheck compliance (no warnings)

If any issues found, fix and commit with conventional message.

### Phase 4: Decide

- If ANY phase made changes this iteration -> continue to next iteration
  (do NOT output the completion promise)
- If all phases were clean (no changes) -> proceed to Phase 5

### Phase 5: Create PR

When all review passes are clean and no changes were made:
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
Completion promise: PR_CREATED (only when all review passes are clean and PR is created)

Review passes:
  1. /simplify     (code quality, reuse, efficiency)
  2. /review       (general review -- skipped if unavailable)
  3. /codex:review (codex review -- skipped if unavailable)
  4. Self-check    (security, conventions, ShellCheck)

The Ralph Loop stop hook will iterate until clean.
To cancel: /cancel-ralph
EOF
