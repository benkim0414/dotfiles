---
title: "Record standing Codex worktree approvals without weakening boundaries"
date: 2026-05-24
category: "workflow-issues"
module: "codex-worktree-approval-workflow"
problem_type: "workflow_issue"
component: "development_workflow"
severity: "medium"
applies_when:
  - "Codex feature or change work starts outside a linked worktree"
  - "superpowers:brainstorming may lead to specs, plans, docs, or code edits"
  - "A user selects finishing-a-development-branch option 4 discard cleanup for an isolated feature worktree"
related_components:
  - "assistant"
  - "documentation"
  - "tooling"
tags:
  - "codex"
  - "worktrees"
  - "approvals"
  - "superpowers"
  - "workflow-isolation"
---

# Record standing Codex worktree approvals without weakening boundaries

## Context

Codex already required repository changes to happen from linked worktrees, but
the instructions did not explicitly say that creating those worktrees was a
standing-approved action. That left routine `superpowers:using-git-worktrees`
setup vulnerable to repeated confirmation prompts before doing the very thing
the workflow required.

The same gap appeared around `superpowers:brainstorming`: when brainstorming
can lead to specs, plans, docs, or code edits, the worktree boundary needs to
exist before generated artifacts are written. The user also wanted
`finishing-a-development-branch` option 4 discard cleanup to be allowed without
another prompt, but only for the isolated feature branch/worktree that the user
has actually chosen to discard.

Session-history search found no relevant prior sessions for this specific
instruction-layer standing approval problem.

## Guidance

Record standing approvals in `codex/.codex/AGENTS.md`, near the existing
approval contract and worktree-isolation sections. Keep the language narrow and
operational:

```markdown
## Standing Worktree Approvals

- Creating a linked worktree through `superpowers:using-git-worktrees` is standing user-approved for feature/change work when the current checkout is not already a linked worktree.
- When `superpowers:brainstorming` may lead to repo edits, ensure a linked worktree exists before writing specs, plans, docs, or code.
- Preserve the repository-local convention `git worktree add .worktrees/<slug> -b <branch>` and continue from `.worktrees/<slug>`.
- `finishing-a-development-branch` option 4 discard cleanup is standing user-approved only after the user has selected discard, and only for removing the confirmed isolated feature worktree/branch.
- Explicit user approval is still required for local merge-to-main, push/PR operations outside the existing auto-review allowance, force operations, writes outside configured workspace roots, unrelated branch/worktree deletion, uncommitted changes, and unmerged user work that was not explicitly abandoned.
```

The important correction is the final boundary sentence. Do not phrase standing
approval as a broad destructive-operation allowance. It must not contradict the
existing auto-review policy or the sensitive-operation rules.

## Why This Matters

Worktree creation is the safe path away from primary-checkout mutation. If an
agent repeatedly asks before creating the linked worktree, the workflow becomes
noisy at exactly the point where it should be automatic.

Discard cleanup is different. Option 4 can remove a worktree and branch, so the
standing approval must be tied to an explicit user choice and a confirmed
isolated target. The wording should make routine cleanup smooth without
authorizing force deletion, unrelated branch deletion, cleanup of uncommitted
work, or removal of unmerged work that the user did not explicitly abandon.

This doc complements existing hook and approval docs: hook-level lifecycle rules
decide what commands are safe to allow, while `AGENTS.md` records the
instruction-layer standing preference that tells Codex when it can proceed
without another question.

## When to Apply

- Feature or change work starts from the primary checkout and should move into a
  linked worktree.
- `superpowers:brainstorming` may produce repository artifacts or code changes.
- The repository uses `.worktrees/<slug>` as the local linked-worktree
  convention.
- The user selects `finishing-a-development-branch` option 4 to discard the
  isolated feature worktree/branch.

Do not apply this pattern to merge-to-main, force pushes, history rewrites,
broad branch deletion, cleanup of unrelated worktrees, writes outside configured
workspace roots, or work with uncommitted/unmerged changes unless the user has
explicitly abandoned that exact work.

## Examples

Before, the worktree requirement existed but the standing approval did not:

```markdown
## Worktree Isolation

- For any change in a Git repository, work from a linked Git worktree rather than the repository's main worktree.
- Use the repository-local convention `git worktree add .worktrees/<slug> -b <branch>` and continue from `.worktrees/<slug>`.
```

After, the approval contract covers the routine setup and keeps sensitive
operations gated:

```markdown
- Creating a linked worktree through `superpowers:using-git-worktrees` is standing user-approved for feature/change work when the current checkout is not already a linked worktree.
- When `superpowers:brainstorming` may lead to repo edits, ensure a linked worktree exists before writing specs, plans, docs, or code.
- `finishing-a-development-branch` option 4 discard cleanup is standing user-approved only after the user has selected discard, and only for removing the confirmed isolated feature worktree/branch.
```

The boundary-preserving clause is not optional:

```markdown
- Explicit user approval is still required for local merge-to-main, push/PR operations outside the existing auto-review allowance, force operations, writes outside configured workspace roots, unrelated branch/worktree deletion, uncommitted changes, and unmerged user work that was not explicitly abandoned.
```

## Related

- `docs/solutions/workflow-issues/inherit-scoped-codex-approvals-in-subagents-2026-05-19.md` -- durable Codex approval policy and the need to document the operational contract in `codex/.codex/AGENTS.md`.
- `docs/solutions/workflow-issues/allow-codex-worktree-lifecycle-with-main-protection.md` -- hook-level command allowances for worktree creation, merge, cleanup, and branch deletion while protecting `main`.
- `docs/solutions/workflow-issues/enforce-codex-workflows-in-linked-worktrees-2026-05-20.md` -- foundation for linked-worktree isolation and hook-level enforcement around registered `.worktrees/` paths.
- `docs/solutions/workflow-issues/superpowers-workflow-reorg-2026-05-19.md` -- broader Superpowers workflow context, including worktree-first behavior and finishing-branch options.
