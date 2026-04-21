---
description: "Review a PR with multiple AI reviewers (Claude Code agents, Codex, Copilot)"
argument-hint: "<pr-number-or-url> [--post]"
allowed-tools: >-
  Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr review:*),
  Bash(gh pr checks:*), Bash(gh api:*),
  Bash(git worktree:*), Bash(git fetch:*), Bash(git branch:*),
  Bash(git rev-parse:*), Bash(git log:*), Bash(git diff:*),
  Bash(cat /tmp/review-pr*), Bash(rm -f /tmp/review-pr*),
  Bash(rm -rf /tmp/review-pr*),
  Bash(ls /tmp/review-pr*), Bash(wc:*), Bash(test:*),
  Bash(kill:*), Bash(sleep:*),
  Read, Grep, Glob, Write(/tmp/review-pr*), Agent
---

## Arguments

$ARGUMENTS

## Pull request context

!`PR_NUM=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || echo "$ARGUMENTS" | tr ' ' '\n' | grep -oE '^[#]?[0-9]+$' | head -1 | tr -d '#'); echo "pr_number: $PR_NUM"`

- PR metadata: !`PR_NUM=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || echo "$ARGUMENTS" | tr ' ' '\n' | grep -oE '^[#]?[0-9]+$' | head -1 | tr -d '#'); gh pr view "$PR_NUM" --json number,title,body,state,author,baseRefName,headRefName,url,reviewDecision`
- PR comments: !`PR_NUM=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || echo "$ARGUMENTS" | tr ' ' '\n' | grep -oE '^[#]?[0-9]+$' | head -1 | tr -d '#'); gh pr view "$PR_NUM" --comments 2>/dev/null | head -200`
- Changed files: !`PR_NUM=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || echo "$ARGUMENTS" | tr ' ' '\n' | grep -oE '^[#]?[0-9]+$' | head -1 | tr -d '#'); gh pr diff "$PR_NUM" --name-only`
- CI status: !`PR_NUM=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || echo "$ARGUMENTS" | tr ' ' '\n' | grep -oE '^[#]?[0-9]+$' | head -1 | tr -d '#'); gh pr checks "$PR_NUM" 2>/dev/null | head -30`

<details><summary>Full diff</summary>

!`PR_NUM=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || echo "$ARGUMENTS" | tr ' ' '\n' | grep -oE '^[#]?[0-9]+$' | head -1 | tr -d '#'); gh pr diff "$PR_NUM"`

</details>

## Background reviewers

```!
"$HOME/.claude/scripts/setup-review-pr.sh" $ARGUMENTS
```

## Your task

Review this pull request using a multi-agent approach. You orchestrate fresh-eyes
reviewer agents (Claude Code subagents) and collect results from Codex and
Copilot running in the background.

### Step 1: Guard checks

Parse the PR metadata above. If the PR state is not OPEN, stop and report why.
Extract: PR number, title, author, base branch, head branch, URL.

### Step 2: Fresh-Eyes Agent Review

Spawn 2 code-reviewer agents **in parallel** (two Agent tool calls in the same
message) using subagent_type: "feature-dev:code-reviewer". Each agent starts
with a clean context window -- no knowledge of this review session.
Pass the full diff (from the PR context above) in each agent's prompt.

**Agent A -- Correctness & Security**

Use the Agent tool with subagent_type: "feature-dev:code-reviewer". Write a
prompt that includes the full PR diff and asks the agent to focus on:
correctness, bugs, logic errors, edge cases, race conditions, input validation
at system boundaries, hardcoded secrets, security vulnerabilities, N+1 patterns.
Instruct it to read files from the PR worktree path (from the background
reviewer context above, field `worktree`) rather than the current directory,
so it sees the PR head rather than any local edits. Report only issues with
confidence >= 80: severity (critical/suggestion/nit), file:line, description,
and a concrete fix.

**Agent B -- Design & Quality**

Use the Agent tool with subagent_type: "feature-dev:code-reviewer". Write a
prompt that includes the full PR diff and asks the agent to focus on: naming,
DRY violations, unnecessary complexity, convention adherence (check CLAUDE.md),
missing error handling, test coverage gaps, dead code, abstraction quality,
consistency with existing codebase patterns.
Instruct it to read files from the PR worktree path (from the background
reviewer context above, field `worktree`) rather than the current directory.
Report only issues with confidence >= 80: severity (critical/suggestion/nit),
file:line, description, and a concrete fix.

Collect findings from both agents. Their combined output is the "Claude Code"
review that will be merged with external reviewer findings in Step 4.

### Step 3: Collect external reviews

Parse the background reviewer context above for PIDs and output file paths.

For each reviewer with a PID (not "none"):
1. Wait for the process to finish (poll with `kill -0 <PID>` every 5s, max 120s)
2. Read the output file: `cat /tmp/review-pr-<N>.<reviewer>.md`
3. Parse findings and merge them with the agent findings from Step 2

If a reviewer was skipped (PID is "none") or its output is empty/missing after
the timeout, log it and continue with the findings you have.

### Step 4: Deduplicate and categorize

Merge findings from all reviewers. If multiple reviewers flagged the same
file+line+issue, combine them into one finding and note all reviewers
(e.g., "[Claude+Codex]").

Present the consolidated review:

```
## Summary
<1-2 sentence overall assessment of the PR>

## Critical Issues (must fix)
- [reviewers] `file:line` -- description

## Suggestions (non-blocking improvements)
- [reviewers] `file:line` -- description

## Nits (style, naming, minor)
- [reviewers] `file:line` -- description

## Positive Observations
- What was done well
```

Include code suggestions (the corrected code) inline where you have a concrete fix.

If the review is clean (no critical issues, few or no suggestions), say so clearly.

### Step 5: Post review (if `--post`)

Check the background reviewer context for `post: true`. If false, display the
review locally and skip to Step 6.

If `post: true`, build a GitHub PR review with inline comments using the API.

**Every finding with a specific file+line becomes an inline review comment**,
regardless of whether it has a code suggestion. This pins each issue to the
exact spot in the diff.

Build a JSON payload and post it:

```bash
# Write the review payload to a temp file, then POST it
# The comments array has one entry per inline finding
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --method POST \
  --input /tmp/review-pr-<N>.review.json
```

The JSON structure:

```json
{
  "event": "COMMENT",
  "body": "## Summary\n...\n\n## Positive Observations\n...",
  "comments": [
    {
      "path": "relative/file/path",
      "line": 42,
      "side": "RIGHT",
      "body": "**[Critical]** [Claude] Description of issue\n\n```suggestion\ncorrected code here\n```"
    },
    {
      "path": "another/file.sh",
      "line": 15,
      "side": "RIGHT",
      "body": "**[Suggestion]** [Claude+Codex] Description without code suggestion"
    }
  ]
}
```

Rules for the inline comment body:
- Start with severity in bold: `**[Critical]**`, `**[Suggestion]**`, or `**[Nit]**`
- Include reviewer attribution: `[Claude]`, `[Codex]`, `[Claude+Codex]`, etc.
- Add a ```` ```suggestion ```` block ONLY when you have a concrete corrected code replacement
- The suggestion block replaces the line(s) at the specified position -- make sure
  the replacement is syntactically correct
- For multi-line suggestions, use `start_line` and `start_side` fields in the comment

The top-level `body` contains the summary and any findings that cannot be pinned
to a specific file+line (architectural concerns, missing tests, etc.).

Extract `{owner}` and `{repo}` from the PR URL in the metadata.

### Step 6: Cleanup

Remove the temp worktree and output files:

```bash
git worktree remove /tmp/review-pr-<N> --force 2>/dev/null || true
git worktree prune 2>/dev/null || true
rm -f /tmp/review-pr-<N>.*
```
