# Codex Worktree Lifecycle Allowance Design

## Context

Codex's PreToolUse worktree guard currently blocks routine cleanup and branch
cleanup commands that are part of the local worktree flow. In the reported
case, `git worktree remove .worktrees/codex-merge-main-approval` was rejected as
cross-boundary targeting, and `git branch -d worktree-codex-merge-main-approval`
was rejected as primary worktree targeting.

That behavior is too broad for the intended workflow. Work under `.worktrees/`
is isolated from the primary checkout and should be treated as normal
development once the worktree has been created. The guard should protect
`main` from harmful operations, not block harmless worktree lifecycle steps.

## Goals

- Allow creation of linked worktrees before any development happens under
  `.worktrees/`.
- Allow file edits, writes, patches, tests, formatting, and similar routine
  operations under registered worktrees in `.worktrees/`.
- Allow the normal local promotion flow from a worktree branch into `main`,
  including checking out `main`, merging the worktree branch, removing the
  worktree, and deleting the merged worktree branch.
- Continue blocking or requiring explicit approval for destructive operations
  that can harm `main`, rewrite history, delete protected branches, or mutate
  unrelated branches.
- Keep the checked-in hook as the source of truth and verify `codex-sync` wires
  `$CODEX_HOME/hooks/worktree-guard.sh` back to that checkout copy.

## Non-Goals

- Do not allow force pushes, history rewrites, hard resets, or deletion of
  `main`.
- Do not allow arbitrary branch deletion unrelated to the current worktree
  cleanup flow.
- Do not treat every path named `.worktrees/<name>` as trusted before Git has
  created or registered it as a worktree.
- Do not redesign unrelated hooks such as atomic commit enforcement.

## Design

The guard should classify operations by their risk to the primary checkout and
protected branches.

Worktree creation is allowed when the command is a normal `git worktree add`
targeting `.worktrees/<name>` inside the repository. This matches the required
workflow: create the isolated worktree first, then perform edits there.

Registered worktree operations are allowed when Git reports the target through
`git worktree list --porcelain`, or when the operation is the initial
`git worktree add` that creates that target. Once registered, writes under the
worktree path are normal workspace mutations and should not be treated as
cross-boundary writes to the primary checkout.

Merge-to-main is allowed for the ordinary local promotion flow: `git checkout
main` or `git switch main`, followed by `git merge <worktree-branch>`. This is
not considered harmful by itself because it intentionally lands isolated work
onto `main` with a normal merge commit or fast-forward. The protected boundary
is destructive mutation of `main`: the guard should still block commands that
reset, rebase, force push, delete, or otherwise rewrite `main`.

Cleanup is allowed for the same lifecycle. `git worktree remove
.worktrees/<name>` should be allowed for a registered worktree. `git branch -d
<worktree-branch>` should be allowed when the branch name matches the known
worktree branch or established worktree branch naming pattern, and the branch is
not `main` or the active branch.

## Error Handling

When the guard blocks an operation, the message should explain the actual
protected resource rather than only saying "cross-boundary." For example,
destructive protected-branch commands should mention the protected branch, and
unregistered `.worktrees/` paths should explain that a worktree must be created
first.

The installed-hook path should remain visible in tests. If `$CODEX_HOME` is
configured, `codex-sync` should keep `$CODEX_HOME/hooks/worktree-guard.sh` as a
symlink to `codex/.codex/hooks/worktree-guard.sh` so local checkout changes are
the live hook behavior after sync.

## Testing

Add or update hook regression tests for the full lifecycle:

- `git worktree add .worktrees/<name> -b <branch>` is allowed.
- File writes and patch operations under the registered worktree are allowed.
- Direct edits under an unregistered `.worktrees/<name>` path are blocked with a
  create-worktree-first message.
- `git checkout main` or `git switch main` is allowed.
- `git merge <worktree-branch>` is allowed.
- `git worktree remove .worktrees/<name>` is allowed for the registered
  worktree.
- `git branch -d <worktree-branch>` is allowed after cleanup when it does not
  target `main` or the active branch.
- Destructive operations against `main`, including hard reset, branch deletion,
  rebase/history rewrite, and force push remain blocked or approval-required.

Also keep the `codex-sync` test that verifies the installed hook symlink points
back to the checkout copy.
