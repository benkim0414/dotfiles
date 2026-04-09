---
allowed-tools: Bash(gh pr view:*), Bash(gh pr edit:*), Bash(gh pr merge:*), Bash(gh pr checks:*), Bash(rm:*), Bash(git fetch:*), Bash(git push:*), Bash(git show:*), Bash(git pull:*), Bash(git checkout:*), Bash(git worktree:*), Bash(git branch:*), Read, Grep, Glob, Write
argument-hint: "[pr-number]"
description: Verify PR test plan, tick completed items, and merge
---

## Context

- Current branch: !`git branch --show-current`
- Arguments: $ARGUMENTS

## Your task

Follow these steps in order.

### Step 1: Fetch and parse the PR

First, determine the PR number:
- Extract the numeric PR number from the arguments. Common formats: `13`, `#13`, `PR #13`, or a URL ending in `/pull/13`. For URLs, take only the number after `/pull/`. For other formats, take the last sequence of digits.
- If no number can be extracted from the arguments AND the current branch is `main` or `master`, stop immediately with: "Error: no PR number provided and current branch is main. Usage: `/merge-pr <number>`"
- If no number can be extracted but the current branch is a feature branch, omit the number to auto-detect from the current branch.

Run `gh pr view` to fetch the PR details as JSON:
- With a PR number: `gh pr view <number> --json number,title,body,state,statusCheckRollup,reviewDecision,url,headRefName`
- Without (auto-detect from branch): `gh pr view --json number,title,body,state,statusCheckRollup,reviewDecision,url,headRefName`

From the result, extract the PR number, title, URL, full body text, state, and reviewDecision.

**Guard check**: If the PR state is `CLOSED`, `DRAFT`, or `MERGED`, or if reviewDecision is `CHANGES_REQUESTED`, stop immediately and report why the PR is not mergeable. Do not proceed to further steps.

Find the `## Test plan` section. Extract every `- [ ]` (unchecked) and `- [x]` (already checked) item under it. Track already-checked items separately as PREVIOUSLY VERIFIED -- they require no re-verification.
If there is no `## Test plan` section, skip to Step 4.

### Step 2: Categorize items by when they can be verified

For each `- [ ]` item, decide whether it can be verified before or after merge:

- **Pre-merge**: items that test the PR branch as-is (unit tests, lint, build commands, file/code property checks)
- **Post-merge**: items that require the merged state (checking main after merge, deployment, integration tests against merged code)
- **Unverifiable**: manual steps involving UI, external services, or human judgment — leave as `- [ ]` and flag them

### Step 3: Pre-merge verification (if any pre-merge items)

For each pre-merge item, attempt automated verification:

a. **Shell commands in backticks**: If the command is within the allowed-tools scope (gh, git), run it. Exit 0 = PASS. Capture stdout and stderr; include them as the failure reason on non-zero exit. Commands outside the allowed-tools scope (e.g., stow, npm, make) cannot be run -- classify these as UNVERIFIABLE.
b. **File/code conditions**: Use Read, Grep, Glob to check the stated condition. Condition met = PASS.
c. Track as PASS or FAIL (with reason).

Update the PR body: replace `- [ ]` with `- [x]` for each PASS item. Leave FAIL, post-merge, and unverifiable items as `- [ ]`.

Only perform the update if at least one item changed from `- [ ]` to `- [x]`. If no items passed, skip the edit call.

To apply the update, write the full updated body to `/tmp/pr-body-<PR_NUMBER>.md` using the Write tool, then run:
```bash
gh pr edit <PR_NUMBER> --body-file /tmp/pr-body-<PR_NUMBER>.md
rm -f /tmp/pr-body-<PR_NUMBER>.md
```

Use the PR number extracted from the context in Step 1.

### Step 4: Check CI status

Run `gh pr checks <PR_NUMBER>` and report failing or pending checks. This step is independent of the test plan and must always run, even if there is no `## Test plan` section.

If `statusCheckRollup` is null in the PR details, there are no configured CI checks — treat CI as not applicable rather than as a failure.
If any required checks are failing, report this clearly and do not proceed without user acknowledgement.

### Step 5: Pre-merge summary

Before merging, output:
```
PR #<number>: <title>
URL: <url>

Test plan:
  PASS              (<n> items ticked off)
  PREVIOUSLY VERIFIED (<n> items — ticked in a prior run)
  FAIL              (<n> items)  [list with reasons]
  DEFERRED          (<n> items)  [will verify after merge]
  UNVERIFIABLE      (<n> items)  [list — manual verification required]

CI: <PASS | FAIL | PENDING | N/A>
```

If there are FAIL items, ask whether to proceed.
If there are UNVERIFIABLE items, ask the user to confirm they were manually verified before proceeding.

### Step 6: Merge

When all pre-merge concerns are resolved, run using the PR number from Step 1:
```bash
gh pr merge <PR_NUMBER> --merge
```

Never use `--squash` or `--rebase`.

After the merge succeeds, delete the remote branch using the `headRefName` from Step 1:
```bash
git push origin --delete <HEAD_BRANCH>
```

If the branch was already deleted (e.g., by GitHub's auto-delete setting), ignore the error.

### Step 7: Post-merge verification (if deferred items exist)

After merge, update the remote-tracking ref:
```bash
git fetch origin main
```

This updates `origin/main` without touching the local `main` ref, which avoids errors when `main` is checked out in another worktree. Then verify deferred items against the merged state using `git show origin/main:<path>` (not `main:<path>`).
Update the PR body with remaining `- [x]` ticks using the same tmpfile approach from Step 3.
Note: `gh pr edit` works on merged PRs — it is correct to update the body of a PR in MERGED state.

### Step 8: Local finalization

After all verification is complete, clean up local state so the workflow for this task is definitively finished.

#### 8a. Find the worktree for the merged branch

Using the `headRefName` from Step 1, find the matching linked worktree:
```bash
git worktree list --porcelain | awk -v branch="refs/heads/<HEAD_BRANCH>" '/^worktree /{wt=$2} $0 == "branch " branch {print wt}'
```

Replace `<HEAD_BRANCH>` with the actual `headRefName`. If no output, there is no worktree to remove — use the no-worktree variant in 8b.

#### 8b. Remove worktree, update main, delete branch

**CRITICAL**: Run all cleanup in a single Bash call. After `git worktree remove` deletes the worktree directory, the Bash tool's CWD no longer exists and any subsequent Bash call will fail with "Path does not exist". The `cd` at the start escapes the doomed directory before removal.

```bash
cd "$(git worktree list | head -1 | awk '{print $1}')" && \
git worktree remove <WORKTREE_PATH>; \
git worktree prune && \
git checkout main && \
git pull --ff-only origin main || git pull origin main; \
git branch -d <HEAD_BRANCH> 2>/dev/null; \
git rev-parse --short HEAD
```

If `git worktree remove` fails because the worktree has uncommitted changes, report the path and error to the user (visible in stderr) but do NOT force-remove it. The remaining commands still run because the commands are joined with `;` after the remove.

If no worktree was found in 8a, skip the remove and prune but still run the rest:
```bash
cd "$(git worktree list | head -1 | awk '{print $1}')" && \
git checkout main && \
git pull --ff-only origin main || git pull origin main; \
git branch -d <HEAD_BRANCH> 2>/dev/null; \
git rev-parse --short HEAD
```

Capture the final `git rev-parse --short HEAD` output as `<SHORT_SHA>` for the summary.

#### 8c. Confirmation

Output a summary:
```
Post-merge cleanup complete:
  - Local main updated to <SHORT_SHA>
  - Worktree removed: <WORKTREE_PATH>  (or "no worktree found")
  - Local branch deleted: <HEAD_BRANCH>  (or "already gone")
```
