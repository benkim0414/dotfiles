# No-PR review rubric

Run this review loop on the feature branch **before** `ExitWorktree("keep")`.
It mirrors the two-agent phase from `/pr:create` without the external CLIs,
ShellCheck gate, `git push`, or `gh pr create`.

## Step 1: Gather diff

```
MERGE_BASE=$(git merge-base HEAD origin/main)
git log --oneline "$MERGE_BASE..HEAD"
git diff "$MERGE_BASE..HEAD"
```

Save the log and diff output for use in Step 2.

## Step 2: Fresh-eyes agent review

Note: the reviewer split below mirrors Phase 2 of pr:create setup.sh and
Step 2 of pr:review SKILL.md -- keep all three in sync if changing agent
focus areas.

Spawn 2 code-reviewer agents **in parallel** (two Agent tool calls in the
same message) using `subagent_type: "feature-dev:code-reviewer"`. Each agent
starts with a clean context window -- no knowledge of the implementation
history. Include the full diff and commit log from Step 1 in each prompt.

**Correctness & Security Reviewer**

Use the Agent tool with `subagent_type: "feature-dev:code-reviewer"`. Write a
prompt that includes the git log and git diff output from Step 1, and asks
the agent to focus on: correctness, bugs, logic errors, edge cases, race
conditions, input validation at system boundaries, hardcoded secrets, security
vulnerabilities. Instruct it to use Read, Grep, Glob for additional file
context, and to only report issues with confidence >= 80, providing for each:
severity (critical/suggestion/nit), file:line, description, and a fix.

**Design & Quality Reviewer**

Use the Agent tool with `subagent_type: "feature-dev:code-reviewer"`. Write a
prompt that includes the git log and git diff output from Step 1, and asks
the agent to focus on: naming, DRY violations, unnecessary complexity,
convention adherence (check CLAUDE.md for project rules), missing error
handling for critical paths, test coverage gaps, dead code, abstraction
quality. Instruct it to use Read, Grep, Glob for additional file context,
and to only report issues with confidence >= 80, providing for each: severity
(critical/suggestion/nit), file:line, description, and a fix.

Wait for both agents to complete. If one agent call fails (subagent type
unavailable or tool error), log the failure and treat that agent's findings
as empty. If **both** fail, do not proceed to Step 4 without any review --
report the failure clearly.

## Step 3: Apply fixes

For each finding from either agent:
1. Evaluate against the current code -- skip false positives or changes that
   would make the code worse. The goal is convergence, not perfection.
2. Fix genuine issues atomically: `git add <specific-files>` (never `-A` or
   `.`) then `git commit` with a conventional message per logical change.
3. Track whether any fixes were applied this iteration.

## Step 4: Loop or exit

- If any fixes were applied in Step 3, return to Step 1 (re-gather diff,
  re-run both reviewers).
- If no fixes were applied and both reviewers return only Nits (no Critical,
  no Suggestions), the loop is clean -- exit.
- If two consecutive iterations report the same residual Nits with no new
  fixes, exit to avoid an infinite nit loop.

## Step 5: Proceed

Review loop complete. Proceed with `ExitWorktree("keep")`, then merge the
feature branch to main and push.

## Out of scope vs /pr:create

The following are intentionally omitted -- they are PR-mode concerns:

- Codex CLI background review
- `gh copilot -p` background review
- ShellCheck gate
- `git push origin HEAD:<branch>`
- `gh pr create`
