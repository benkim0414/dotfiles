# Codex Merge-to-Main Approval Design

## Context

Codex currently uses an `on-request` approval policy with an auto-review layer for
routine repository work. Existing workflow docs already separate routine PR and
branch commands from sensitive merge operations, but the merge-to-main boundary
should be explicit for both PR and no-PR worktree completion flows.

The desired behavior is an approval prompt, not a hard block. When Codex is about
to run a merge operation that lands work on `main`, it should request direct user
approval. After approval, the merge may proceed.

## Goals

- Require direct user approval before Codex runs PR merges into `main`, including
  `gh pr merge --merge`.
- Require direct user approval before Codex runs local no-PR merges into `main`,
  including the worktree completion pattern of switching to `main` and merging a
  development branch.
- Preserve auto-review for routine repository work such as status inspection,
  diffs, checks, PR creation, PR updates, issue operations, fetch, pull, and
  ordinary non-force current-branch pushes.
- Keep the change in policy and instruction surfaces rather than adding a hook
  that denies merge commands.

## Non-Goals

- Do not block merge commands through `atomic-commits.sh`, `worktree-guard.sh`, or
  a new hook.
- Do not change worktree write guards, atomic commit enforcement, sandbox mode,
  or approval mode.
- Do not introduce command parsing that attempts to prove every possible shell
  spelling of a merge target.
- Do not change the established merge style; PR merges should still use merge
  commits when approved.

## Design

Update the durable Codex approval contract so merge-to-main operations are
classified as sensitive operations requiring direct user approval and excluded
from auto-review.

The approval policy should explicitly name both command families:

- GitHub/PR merge operations such as `gh pr merge`, especially `gh pr merge
  --merge`.
- Local Git merge-to-main operations such as `git checkout main` followed by
  `git merge <branch>`, or equivalent agent-initiated commands that merge a
  development branch into `main`.

The policy should keep routine work eligible for auto-review. In particular, PR
creation and review preparation should remain low-friction; the approval boundary
is the operation that lands work on `main`.

## Files

- `codex/.codex/config.base.toml`: durable source for the auto-review policy.
  Update `[auto_review].policy` wording to call out merge-to-main and `gh pr
  merge` as direct-user-approval operations.
- `codex/.codex/AGENTS.md`: agent-readable approval contract. Mirror the same
  merge-to-main rule so Codex sessions and subagents receive consistent
  instructions.
- `codex/.codex/config.toml`: generated local config from `codex-sync`. Regenerate
  for verification if needed, but do not commit it if it remains ignored.

## Error Handling

If Codex cannot determine whether a requested merge lands on `main`, it should
treat the operation as approval-sensitive and ask the user before running it.
This conservative behavior applies only to merge operations, not routine PR or
branch inspection commands.

If the user approves, Codex can run the requested merge command. If the user
declines, Codex should stop the merge path and leave the branch/worktree state
unchanged.

## Testing

Verification is text/config based:

- Confirm `codex/.codex/config.base.toml` preserves routine auto-review wording.
- Confirm `codex/.codex/config.base.toml` names `gh pr merge`, GitHub merge
  operations, and local merge-to-main operations as requiring direct user
  approval.
- Confirm `codex/.codex/AGENTS.md` mirrors the same approval contract.
- Run the existing Codex sync/config tests if the implementation changes config
  content or regeneration expectations.
