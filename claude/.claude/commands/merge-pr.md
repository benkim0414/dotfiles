---
allowed-tools: Bash(gh pr view:*), Bash(gh pr edit:*), Bash(gh pr merge:*), Bash(gh pr checks:*), Bash(gh api:*), Bash(rm:*), Bash(git fetch:*), Bash(git push:*), Bash(git show:*), Bash(git pull:*), Bash(git checkout:*), Bash(git worktree:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(pwd), Read, Grep, Glob, Write, ExitWorktree
argument-hint: "[pr-number-or-url]"
description: Verify PR test plan, tick completed items, and merge
---

## Context

- Current branch: !`git branch --show-current`
- Arguments: $ARGUMENTS

### Pre-loaded PR data and CI status

!`PR_NUM=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || echo "$ARGUMENTS" | tr ' ' '\n' | grep -oE '^[#]?[0-9]+$' | head -1 | tr -d '#'); REPO=$(echo "$ARGUMENTS" | grep -oE 'github\.com/[^/]+/[^/]+' | sed 's|github\.com/||' || true); REPO_FLAG=""; if [ -n "$REPO" ]; then REPO_FLAG="-R $REPO"; fi; if [ -n "$PR_NUM" ]; then echo "## Repo: ${REPO:-<cwd>}"; echo "## PR metadata"; gh pr view "$PR_NUM" $REPO_FLAG --json number,title,body,state,statusCheckRollup,reviewDecision,url,headRefName,baseRefName 2>/dev/null; echo; echo "## CI checks"; gh pr checks "$PR_NUM" $REPO_FLAG 2>/dev/null | head -30; fi`

## Your task

Follow these steps in order.

### Step 1: Parse the PR

Use the pre-loaded PR data above. If the pre-loaded data is empty (no PR number in arguments):
- If the current branch is `main` or `master`, stop immediately with: "Error: no PR number provided and current branch is main. Usage: `/merge-pr <number>`"
- If on a feature branch, run `gh pr view --json number,title,body,state,statusCheckRollup,reviewDecision,url,headRefName` to auto-detect from the current branch.

From the pre-loaded data, note the **Repo** line. If it shows an `owner/repo` value (extracted from a URL argument), this is a **cross-repo PR**. You MUST pass `-R <owner/repo>` to every `gh` command for the rest of this workflow. If it shows `<cwd>`, the PR belongs to the current repo and no `-R` flag is needed.

From the PR data, extract the PR number, title, URL, full body text, state, and reviewDecision.

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
gh pr edit <PR_NUMBER> [-R <REPO>] --body-file /tmp/pr-body-<PR_NUMBER>.md
rm -f /tmp/pr-body-<PR_NUMBER>.md
```

Use the PR number extracted from the context in Step 1. Include `-R <REPO>` if this is a cross-repo PR (see Step 1).

### Step 4: Check CI status

Use the pre-loaded CI status above. If it was empty (no PR number in arguments), run `gh pr checks <PR_NUMBER> [-R <REPO>]` now (include `-R` for cross-repo PRs). Report failing or pending checks. This step is independent of the test plan and must always run, even if there is no `## Test plan` section.

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
gh pr merge <PR_NUMBER> [-R <REPO>] --merge
```

Never use `--squash` or `--rebase`. Include `-R <REPO>` for cross-repo PRs.

After the merge succeeds, delete the remote branch using the `headRefName` from Step 1:
```bash
git push origin --delete <HEAD_BRANCH>
```

If the branch was already deleted (e.g., by GitHub's auto-delete setting), ignore the error.

**Cross-repo PRs**: Skip the `git push origin --delete` command -- you don't have a local remote for the other repo's branches.

### Step 7: Post-merge verification (if deferred items exist)

**Cross-repo PRs**: Skip the `git fetch` and `git show` commands below -- you cannot fetch from a repo that isn't a local remote. Instead, verify deferred items using `gh api repos/<REPO>/contents/<path>?ref=main` or simply mark them as UNVERIFIABLE. Still update the PR body via `gh pr edit [-R <REPO>]` as described.

**Same-repo PRs**: After merge, update the remote-tracking ref:
```bash
git fetch origin main
```

This updates `origin/main` without touching the local `main` ref, which avoids errors when `main` is checked out in another worktree. Then verify deferred items against the merged state using `git show origin/main:<path>` (not `main:<path>`).

Update the PR body with remaining `- [x]` ticks using the same tmpfile approach from Step 3.
Note: `gh pr edit` works on merged PRs — it is correct to update the body of a PR in MERGED state.

### Step 8: Local finalization

After all verification is complete, clean up local state so the workflow for this task is definitively finished.

**Cross-repo PRs**: Skip Steps 8a-8c entirely -- there is no local branch or worktree to clean up for a PR in another repository. Output a summary and stop:
```
Cross-repo merge complete:
  PR #<number> merged in <REPO>
  No local cleanup needed (cross-repo PR)
```

#### 8a. Escape worktree CWD (if needed)

**CRITICAL**: If the Bash tool's CWD is inside a linked worktree, the harness locks CWD to that path. Running `cd` in a Bash command does NOT persist — the harness resets CWD on the next call. If the worktree directory is then deleted, every subsequent Bash call fails with "Path does not exist" (harness rejects before execution), creating an unrecoverable loop.

The **only** way to release the harness CWD lock is `ExitWorktree()`.

Detect if CWD is inside a linked worktree:
```bash
git rev-parse --absolute-git-dir && git rev-parse --git-common-dir
```

If the two paths differ, CWD is in a linked worktree. Call `ExitWorktree("keep")` to return CWD to the main worktree before proceeding. Ignore the hook guidance about waiting for the user to merge — the merge already happened in Step 6.

If the paths are the same (or the first command fails because CWD no longer exists), CWD is already in the main worktree — proceed directly to 8b.

**Recovery**: If Bash calls fail with "Path does not exist", the CWD is already stuck in a deleted directory. Ask the user to run `! cd ~/workspace/<repo>` at the Claude Code prompt, then retry from this step.

#### 8b. Verify CWD and find the worktree for the merged branch

Confirm CWD is the main repo root:
```bash
pwd
```

Verify the output is NOT a `.claude/worktrees/` path. If it is, stop and ask the user to escape manually with `! cd ~/workspace/<repo>`.

Using the `headRefName` from Step 1, find the matching linked worktree:
```bash
git worktree list --porcelain | awk -v branch="refs/heads/<HEAD_BRANCH>" '/^worktree /{wt=$2} $0 == "branch " branch {print wt}'
```

Replace `<HEAD_BRANCH>` with the actual `headRefName`. If no output, there is no worktree to remove — skip to 8c (the worktree-remove part).

#### 8c. Remove worktree, update main, delete branch

Now that CWD is safely outside the worktree, remove it and update local state:

```bash
if [ -d "<WORKTREE_PATH>" ]; then git worktree remove "<WORKTREE_PATH>"; fi; \
git worktree prune && \
git checkout main && \
git pull --ff-only origin main || git pull origin main; \
git branch -d <HEAD_BRANCH> 2>/dev/null; \
git rev-parse --short HEAD
```

The `[ -d ... ]` guard handles the case where the worktree directory was already deleted (e.g., by `ExitWorktree("remove")` or manual cleanup). `git worktree prune` cleans up stale metadata regardless.

If `git worktree remove` fails because the worktree has uncommitted changes, report the path and error to the user (visible in stderr) but do NOT force-remove it. The remaining commands still run because the commands are joined with `;` after the conditional.

If no worktree was found in 8b, skip the remove and prune but still run the rest:
```bash
git checkout main && \
git pull --ff-only origin main || git pull origin main; \
git branch -d <HEAD_BRANCH> 2>/dev/null; \
git rev-parse --short HEAD
```

Capture the final `git rev-parse --short HEAD` output as `<SHORT_SHA>` for the summary.

#### 8d. Confirmation

Output a summary:
```
Post-merge cleanup complete:
  - Local main updated to <SHORT_SHA>
  - Worktree removed: <WORKTREE_PATH>  (or "no worktree found")
  - Local branch deleted: <HEAD_BRANCH>  (or "already gone")
```
