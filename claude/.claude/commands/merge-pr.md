---
allowed-tools: Bash(gh pr view:*), Bash(gh pr edit:*), Bash(gh pr merge:*), Bash(gh pr checks:*), Bash(rm:*), Bash(git fetch:*), Read, Grep, Glob, Write
description: Verify PR test plan, tick completed items, and merge
---

## Context

- Current branch: !`git branch --show-current`
- PR details: !`gh pr view --json number,title,body,state,statusCheckRollup,reviewDecision,url`

## Your task

Follow these steps in order.

### Step 1: Parse the PR

From the injected PR details, extract the PR number, title, URL, and full body text.
Find the `## Test plan` section and extract every `- [ ]` checklist item under it.
If there is no `## Test plan` section, skip to Step 4.

### Step 2: Categorize items by when they can be verified

For each `- [ ]` item, decide whether it can be verified before or after merge:

- **Pre-merge**: items that test the PR branch as-is (unit tests, lint, build commands, file/code property checks)
- **Post-merge**: items that require the merged state (checking main after merge, deployment, integration tests against merged code)
- **Unverifiable**: manual steps involving UI, external services, or human judgment — leave as `- [ ]` and flag them

### Step 3: Pre-merge verification (if any pre-merge items)

For each pre-merge item, attempt automated verification:

a. **Shell commands in backticks**: Run the command. Exit 0 = PASS. Capture stdout and stderr; include them as the failure reason on non-zero exit.
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
  PASS         (<n> items ticked off)
  FAIL         (<n> items)  [list with reasons]
  DEFERRED     (<n> items)  [will verify after merge]
  UNVERIFIABLE (<n> items)  [list — manual verification required]

CI: <PASS | FAIL | PENDING | N/A>
```

If there are FAIL items, ask whether to proceed.
If there are UNVERIFIABLE items, ask the user to confirm they were manually verified before proceeding.

### Step 6: Merge

When all pre-merge concerns are resolved, run using the PR number from Step 1:
```bash
gh pr merge <PR_NUMBER> --merge --yes
```

Never use `--squash` or `--rebase`.

### Step 7: Post-merge verification (if deferred items exist)

After merge, land the merged commits locally with:
```bash
git fetch origin main:main
```

This updates the local main ref from any branch or worktree without requiring a checkout. Then verify deferred items against the merged state using the updated local main.
Update the PR body with remaining `- [x]` ticks using the same tmpfile approach from Step 3.
Note: `gh pr edit` works on merged PRs — it is correct to update the body of a PR in MERGED state.
