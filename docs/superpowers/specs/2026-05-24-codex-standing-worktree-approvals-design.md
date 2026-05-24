# Codex Standing Worktree Approvals Design

## Problem

Codex currently asks for user confirmation around workflow actions that the user
wants to treat as standing preferences:

- creating a linked worktree when feature/change work starts from the primary
  checkout;
- running `superpowers:using-git-worktrees` before brainstorming-driven work
  reaches repo edits when the current checkout is not already isolated;
- using `finishing-a-development-branch` option 4 to discard the isolated
  feature worktree/branch.

The existing Codex instructions already require linked worktrees for repository
changes, but they do not state that these specific actions are pre-approved.

## Goals

- Make the preference Codex-only.
- Tell Codex to run `superpowers:using-git-worktrees` before repo-editing
  brainstorming or implementation work when the current checkout is not already
  a linked worktree.
- Treat creation of a repository-local linked worktree under `.worktrees/<slug>`
  as standing user-approved.
- Treat `finishing-a-development-branch` option 4 discard cleanup as standing
  user-approved when it only removes the isolated feature worktree/branch.
- Keep sensitive operations protected: local merge-to-main, push/PR, force
  operations, destructive cleanup outside the isolated worktree, and removal of
  unmerged user work still require explicit approval.

## Non-Goals

- Do not change Superpowers skill source files.
- Do not rewrite the Codex worktree guard hook.
- Do not change Claude-wide or repo-wide behavior outside Codex instructions.
- Do not globally disable sandbox or approval policy.

## Approach

Update `codex/.codex/AGENTS.md` because it is the Codex-facing instruction file
that already documents the approval contract and worktree isolation behavior.

Add a small standing-approval clarification near the existing approval and
worktree sections:

1. Worktree creation through `superpowers:using-git-worktrees` is pre-approved
   for Codex feature/change work when the current checkout is not already
   isolated.
2. If `superpowers:brainstorming` is used for work that can lead to repository
   edits, Codex should ensure a linked worktree exists before writing specs,
   plans, docs, or code.
3. The approved location remains the repository convention:
   `.worktrees/<slug>`.
4. `finishing-a-development-branch` option 4 is pre-approved only for cleanup of
   the isolated feature worktree/branch.
5. The standing approval does not cover unrelated worktrees, unrelated branches,
   unmerged work not explicitly abandoned by the user, merge-to-main, push/PR,
   force operations, or writes outside the configured workspace roots.

## Error Handling

If worktree creation fails because of sandbox restrictions, Codex should follow
the normal `using-git-worktrees` fallback: request escalation or report the
blocker rather than editing the primary checkout.

If discard cleanup finds uncommitted changes, an unmerged branch, or a target
outside the current isolated worktree, Codex should stop and ask for explicit
approval.

## Testing

Verification should cover:

- The updated `codex/.codex/AGENTS.md` contains the Codex-only standing approval
  language.
- The language preserves the existing requirement for explicit approval on
  local merge-to-main, push/PR, destructive operations outside the isolated
  worktree, and unmerged user work.
- Git diff shows only the intended Codex instruction/spec/plan changes for this
  workflow update.
