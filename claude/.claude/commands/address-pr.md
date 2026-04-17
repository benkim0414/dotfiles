---
description: "Address all review comments in a PR"
argument-hint: "<pr-number-or-url>"
allowed-tools: >-
  Bash(gh api:*),
  Bash(git add:*), Bash(git commit:*), Bash(git push origin:*),
  Bash(git fetch:*), Bash(git checkout:*), Bash(git branch:*),
  Bash(git rev-parse:*), Bash(git log:*), Bash(git diff:*), Bash(git status),
  Bash(cat /tmp/address-pr*), Bash(rm -f /tmp/address-pr*),
  Read, Write, Edit, MultiEdit, Grep, Glob,
  Write(/tmp/address-pr*), Agent, EnterWorktree
---

## Arguments

$ARGUMENTS

## Context

```!
"$HOME/.claude/scripts/setup-address-pr.sh" $ARGUMENTS
```

## Your task

Address all unresolved review comments on this PR. Make code changes, commit
each fix atomically, push once, then reply to every comment on GitHub.

### Step 1: Guard checks and branch setup

Parse the YAML header above.

- If `state` is not `OPEN`, stop and report why the PR cannot be addressed.
- If `branch_match` is `true`, you are already on the PR branch -- proceed.
- If `branch_match` is `false`, enter the PR branch:
  1. Run `EnterWorktree` to create an isolated worktree.
  2. Fetch and checkout the head branch:
     ```bash
     git fetch origin <head_branch> --no-tags
     git checkout <head_branch>
     ```

Extract and remember: `pr_number`, `owner_repo`, `pr_author`, `head_branch`.

### Step 2: Classify and filter comments

Analyze all pre-loaded comments (inline, general, and review bodies).

**Filter out:**
- Comments authored by `pr_author` (self-comments, acknowledgments)
- Bot comments (`author_association` is `BOT`, or username contains `[bot]`)
- Outdated inline comments where `position` is `null` -- note these in the summary as "outdated, skipped"
- Threads (grouped by `in_reply_to_id`) where the **last** reply is from `pr_author` with acknowledgment language (e.g., "done", "fixed", "addressed", "will do", "good point")

**Group** inline comments by thread: root comment + all replies sharing the same `in_reply_to_id` (or replying to the root `id`). The actionable request is the synthesis of the full thread, not just the first message.

**Classify** each remaining item as one of:
- **Actionable code change** -- the comment requests a specific code modification
- **Question** -- the reviewer is asking for clarification
- **Architectural/design** -- broader concern without a single code fix

**Present the classification** to the user before proceeding:
```
Found <N> unaddressed comments:
  <n> actionable code changes
  <n> questions
  <n> architectural/design discussions
  <n> outdated (skipped)
  <n> already acknowledged (skipped)

Proceeding to address them.
```

### Step 3: Address each comment with an atomic commit

Process actionable comments in **file path + line number** order for locality.
Each actionable comment gets its own commit.

For each **actionable code change**:

1. **Read** the relevant file using the Read tool. Use the pre-loaded diff and
   `diff_hunk` for initial understanding, but read the full file for complete context.
2. **Understand** context -- use Grep/Glob if the change references other parts
   of the codebase.
3. **Apply** the change using Edit or MultiEdit.
4. **Stage and commit** atomically:
   ```bash
   git add <changed-files>
   git commit -m "fix(<scope>): <description>

   Addresses review comment by @<reviewer> on <file>:<line>."
   ```
   Use conventional commit format. The scope should be the component or area
   affected (e.g., `bin`, `config`, `tmux`), not "review".
5. **Record** the comment ID, commit SHA (`git rev-parse --short HEAD`), and
   a one-line description for the reply phase.

For **questions**: draft a reply based on the codebase context. No code change.

For **architectural/design** comments: draft a reply acknowledging the concern
and explaining the current approach. Flag that it may need the PR author's input.

If an **edit fails** (file moved, wrong line, etc.), do not stop. Log the
failure and draft a reply explaining the issue. Continue to the next comment.

If two comments **conflict** (request contradictory changes to the same code),
address the first and draft a reply to the second noting the conflict and
deferring to the PR author.

### Step 4: Push all commits

After all actionable comments are addressed:

```bash
git push origin HEAD:<head_branch>
```

Single push -- one CI run, one notification batch.

If the push fails, report the error and **do not** proceed to Step 5 (replies
should reference pushed commits).

### Step 5: Reply to all comments

After the push succeeds, reply to every processed comment on GitHub.

**Inline comment replies** (thread replies via the review comments API):
```bash
gh api "repos/<owner_repo>/pulls/<pr_number>/comments/<comment_id>/replies" \
  --method POST -f body="Addressed in <sha> -- <description>."
```

**Questions** (inline reply):
```bash
gh api "repos/<owner_repo>/pulls/<pr_number>/comments/<comment_id>/replies" \
  --method POST -f body="<answer to the question>"
```

**Architectural/design** (inline reply):
```bash
gh api "repos/<owner_repo>/pulls/<pr_number>/comments/<comment_id>/replies" \
  --method POST -f body="<acknowledgment and explanation>"
```

**General PR comment replies** (issue-level comments -- not inline):
```bash
gh api "repos/<owner_repo>/issues/<pr_number>/comments" \
  --method POST -f body="Re: @<reviewer>'s comment about <topic>:

<response>"
```

### Step 6: Summary

Output a summary table:

```
## Address PR Summary

PR #<number>: <title>
URL: <url>
Commits pushed: <count>

| # | Comment | Author | Type | Commit | Action |
|---|---------|--------|------|--------|--------|
| 1 | #<id>   | @user  | fix  | <sha>  | <desc> |
| 2 | #<id>   | @user  | question | -- | Replied |
| 3 | #<id>   | @user  | outdated | -- | Skipped |
```
