# Codex Worktree Git Approval Design

## Context

Codex currently uses a user-level `PreToolUse` hook,
`codex/.codex/hooks/atomic-commits.sh`, to enforce atomic commit habits. The hook
blocks broad staging and commit-all commands such as `git add .`, `git add -A`,
`git add -u`, `git commit -a`, and `git commit -am`.

Codex also runs with `approval_policy = "on-request"`, so commands that leave
the sandbox or otherwise require approval can interrupt work. The desired change
is to reduce approval friction for Git operations when Codex is already working
inside a linked Git worktree, while preserving the atomic commit convention in
all checkouts.

## Goal

Allow otherwise valid Codex Git operations to proceed without approval when the
current checkout is any linked Git worktree, without weakening atomic commit
enforcement.

## Non-Goals

- Do not allow broad staging or commit-all commands in worktrees.
- Do not trust worktrees based on directory names such as `.claude/worktrees/`.
- Do not weaken approval policy for non-Git shell commands.
- Do not globally switch Codex to a less restrictive approval mode.
- Do not change the existing conventional commit message hook.

## Recommended Approach

Keep atomic commit enforcement and Git approval trust as separate policies.

Atomic commit enforcement should continue to run in every checkout. Worktree
trust should apply only to approval handling for Git commands that already pass
the atomic commit checks.

## Worktree Detection

Detect linked worktrees through Git metadata, not path conventions:

1. Confirm the current directory is inside a non-bare Git repository.
2. Read `git rev-parse --absolute-git-dir`.
3. Read and resolve `git rev-parse --git-common-dir`.
4. Treat the checkout as a linked worktree when the absolute Git dir differs
   from the resolved common Git dir.

This matches the existing Claude hook pattern and works for any linked Git
worktree location.

## Behavior

Inside a linked worktree:

- Allow valid Git operations without an approval prompt when Codex can express
  that approval decision.
- Continue blocking broad staging commands:
  `git add .`, `git add -A`, `git add --all`, `git add -u`, and equivalent broad
  pathspecs.
- Continue blocking commit-all commands:
  `git commit -a`, `git commit -am`, and `git commit --all`.

Outside a linked worktree:

- Preserve the current atomic commit hook behavior.
- Preserve the current approval posture.

Examples inside a linked worktree:

- `git status --short`: allowed.
- `git add src/app.ts tests/app.test.ts`: allowed.
- `git commit -m "fix(app): handle empty state"`: allowed.
- `git branch`, `git switch`, `git merge`, `git rebase`, `git reset`,
  `git restore`, and `git stash`: allowed if they pass Codex's normal command
  safety checks.
- `git add .`: denied by the atomic commit hook.
- `git commit -am "fix(app): update"`: denied by the atomic commit hook.

## Implementation Constraint

Before implementation, verify how Codex can grant approval from local policy:

- If `PreToolUse` hooks support an explicit allow decision that bypasses an
  approval prompt, add worktree-aware allow output after the atomic commit
  checks pass.
- If hooks can only deny, use Codex config rules if they support a worktree-
  scoped Git allow policy.
- If neither mechanism can express "allow Git without approval only in linked
  worktrees," keep atomic enforcement unchanged and document the limitation
  instead of weakening global approval settings.

## Components

- `codex/.codex/hooks/atomic-commits.sh`: retain the existing deny checks and,
  if supported, add worktree-aware allow behavior only after those checks.
- `codex/.codex/tests/test-atomic-commits-hook.sh`: add linked-worktree fixture
  tests proving broad staging is still denied in worktrees.
- Codex config files: only change approval-related configuration if Codex
  supports a scoped rule that is limited to Git commands in linked worktrees.

## Testing

Verification should cover:

- Existing primary-checkout tests still deny broad staging and commit-all
  commands.
- A temporary linked worktree allows normal Git commands.
- The linked worktree still denies `git add .`, `git add -A`, `git add -u`,
  `git commit -a`, and `git commit -am`.
- The primary checkout keeps the current approval posture.
- Non-Git commands do not gain extra approval bypasses.

## Error Handling

- If worktree detection fails or the current directory is not in a Git
  repository, fall back to the current conservative behavior.
- If Codex does not support scoped approval bypasses, report that limitation
  clearly and keep the atomic commit guard intact.
- If a Git command is denied by the atomic convention, keep the existing
  corrective message directing Codex to stage explicit files for one logical
  change.
