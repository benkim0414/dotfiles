---
title: "Allow Codex worktree lifecycle while protecting main"
date: "2026-05-22"
last_updated: "2026-05-22"
category: "workflow-issues"
module: "dotfiles/codex"
problem_type: "workflow_issue"
component: "development_workflow"
severity: "high"
applies_when:
  - "Codex PreToolUse hooks block normal git worktree creation, merge, or cleanup commands"
  - "Work under .worktrees/ should be allowed once Git has registered the linked worktree"
  - "Local worktree branches need to be merged back into main without allowing history rewrites"
  - "Branch cleanup must allow the intended worktree branch without allowing unrelated branch deletion"
related_components:
  - "tooling"
  - "assistant"
  - "git"
tags:
  - "codex"
  - "worktrees"
  - "hooks"
  - "main-protection"
  - "git"
  - "workflow-enforcement"
---

# Allow Codex Worktree Lifecycle While Protecting Main

## Context

Codex's worktree guard originally treated `.worktrees/` targets and primary
checkout commands as approval-sensitive by default. That protected `main`, but
it also blocked the intended local workflow:

- create a linked worktree under `.worktrees/`
- edit and test inside the linked worktree
- switch the primary checkout to `main`
- merge the worktree branch into `main`
- remove the linked worktree
- delete the merged worktree branch

The correct boundary is not "never touch `.worktrees/`" or "never check out
`main`." The boundary is "allow normal non-destructive lifecycle operations, but
keep destructive mutation of `main` and unrelated branch mutation guarded."

## Guidance

Use Git metadata instead of path names as the source of trust.

- Allow `git worktree add .worktrees/<slug> -b <branch>` as the recovery path
  from a primary checkout, but reject nested targets and force flags.
- Treat writes under `.worktrees/<slug>` as safe only after `git worktree
  list --porcelain` reports that path as a linked worktree.
- Allow `git checkout main` and `git switch main`; these commands select the
  branch and do not rewrite it.
- Allow `git merge <branch>` only when the current branch is protected
  (`main` or `master`) and `<branch>` is a registered worktree branch.
- Allow `git branch -d <branch>` for cleanup, but reject protected branches,
  the active branch, force deletion, and unrelated branch names.
- After `git worktree remove`, the removed branch is no longer present in
  `git worktree list --porcelain`. If the workflow needs post-remove branch
  cleanup, use a narrow convention such as `worktree-*`; do not allow broad
  substring checks like `*worktree*`.

Keep destructive operations approval-required even when the branch or path looks
like part of the lifecycle:

```bash
git worktree remove --force .worktrees/feature
git branch -D worktree-feature
git branch -d main
git reset --hard HEAD
git rebase HEAD~1
git push --force origin main
```

## Why This Matters

Worktree automation needs a precise safety model. Overly strict guards trap the
agent in the primary checkout and block cleanup. Overly broad allow rules create
silent bypasses for primary-checkout mutation.

The subtle failure modes are in command classification order and lifecycle
state transitions:

- If `git worktree add .worktrees/*` is treated as read-only before stricter
  lifecycle validation runs, `--force` or nested target paths can bypass the
  intended checks.
- If `git merge <branch>` only verifies that `<branch>` is a registered
  worktree branch, Codex can merge into a non-main primary branch. The current
  branch must also be checked.
- If `git branch -d <branch>` relies only on the live worktree registry, it
  fails after `git worktree remove`; if it falls back to `*worktree*`, it allows
  unrelated branch deletion. Use a narrow cleanup convention.

## When to Apply

Apply this pattern when a hook or approval policy must support local worktree
development while keeping `main` protected from destructive operations.

It is especially relevant for Codex hooks that inspect shell commands,
`apply_patch`, MCP executor payloads, and generated config sync tests.

## Verification Pattern

Regression tests should cover the complete lifecycle, not just independent
command classification:

1. Allow `git worktree add .worktrees/<slug> -b worktree-<slug>`.
2. Allow writes under the registered `.worktrees/<slug>` path.
3. Reject writes under an unregistered `.worktrees/<slug>` path.
4. Allow `git checkout main` and `git switch main`.
5. Allow `git merge worktree-<slug>` only while on `main`.
6. Reject the same merge while on an unrelated branch.
7. Allow `git worktree remove .worktrees/<slug>`.
8. Allow `git branch -d worktree-<slug>` after removal.
9. Reject unrelated branch cleanup such as `git branch -d unrelated-worktree-cleanup`.
10. Keep destructive `main` operations approval-required.

Also verify the installed hook path remains wired through `codex-sync` so the
checked-in hook is the source of truth for `$CODEX_HOME/hooks/worktree-guard.sh`.

## Related

- `docs/solutions/workflow-issues/enforce-codex-workflows-in-linked-worktrees-2026-05-20.md`
- `docs/superpowers/specs/2026-05-22-codex-worktree-lifecycle-allowance-design.md`
- `docs/superpowers/plans/2026-05-22-codex-worktree-lifecycle-allowance.md`
