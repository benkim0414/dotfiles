# Codex Worktree Lifecycle Allowance Implementation Plan

**Spec:** `docs/superpowers/specs/2026-05-22-codex-worktree-lifecycle-allowance-design.md`

**Goal:** Make Codex's worktree guard allow normal isolated worktree creation,
development, merge-to-main, and cleanup while continuing to block destructive
operations against `main` and unrelated branch mutations.

## Task 1: Add Lifecycle Regression Tests

- [ ] Modify `codex/.codex/tests/test-worktree-guard-hook.sh`.
- [ ] Add fixture coverage for a project-local `.worktrees/<name>` worktree.
- [ ] Assert `git worktree add .worktrees/<name> -b <branch>` is allowed before
  the directory exists.
- [ ] Assert file writes and patch-style operations under the registered
  `.worktrees/<name>` worktree are allowed from the primary checkout context.
- [ ] Assert direct edits under an unregistered `.worktrees/<name>` directory
  still require approval and explain that a worktree must be created first.
- [ ] Assert `git checkout main`, `git switch main`, and `git merge
  <worktree-branch>` are allowed.
- [ ] Assert `git worktree remove .worktrees/<name>` is allowed for a registered
  worktree.
- [ ] Assert `git branch -d <worktree-branch>` is allowed for worktree cleanup,
  while deleting `main`, the active branch, or an unrelated branch is blocked or
  approval-required.
- [ ] Run `bash codex/.codex/tests/test-worktree-guard-hook.sh` and confirm the
  new assertions fail before implementation.

## Task 2: Implement Guard Classification

- [ ] Modify `codex/.codex/hooks/worktree-guard.sh`.
- [ ] Add helpers to identify local `git worktree add`, `git worktree remove`,
  safe checkout/switch-to-main, safe merge, and safe worktree branch deletion
  command shapes.
- [ ] Use Git worktree registry metadata where possible instead of trusting path
  names alone.
- [ ] Permit initial `git worktree add` into `.worktrees/<name>` when the target
  is inside the current repository and uses a single child path.
- [ ] Permit writes under registered linked worktrees, including project-local
  worktrees under `.worktrees/`.
- [ ] Keep primary checkout writes that are not safe lifecycle commands behind
  explicit approval.
- [ ] Keep destructive `main` operations blocked or approval-required:
  `reset --hard`, deleting `main`, force pushes, rebases/history rewrites, and
  unrelated branch deletion.

## Task 3: Align Policy and Sync Tests

- [ ] Review `codex/.codex/config.base.toml`, `codex/.codex/config.toml`, and
  `codex/.codex/tests/test-codex-sync-hooks.sh` for stale language that says
  ordinary local merge-to-main always requires direct user approval.
- [ ] Update policy text and assertions only where they contradict the approved
  lifecycle allowance.
- [ ] Preserve assertions that `$CODEX_HOME/hooks/worktree-guard.sh` is symlinked
  to the checkout copy.

## Task 4: Verify and Commit

- [ ] Run `bash codex/.codex/tests/test-worktree-guard-hook.sh`.
- [ ] Run `bash codex/.codex/tests/test-codex-sync-hooks.sh`.
- [ ] Run `bash codex/.codex/tests/test-atomic-commits-hook.sh`.
- [ ] Inspect `git diff` for scope and accidental primary-checkout edits.
- [ ] Commit the implementation with a `fix(codex): ...` message.
- [ ] Request code review, resolve any Critical or Important findings, and run
  final verification again.
