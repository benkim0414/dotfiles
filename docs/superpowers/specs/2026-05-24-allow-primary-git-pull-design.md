# Allow Primary Checkout Git Pull Design

## Context

The Codex worktree guard currently blocks `git pull` in the primary checkout.
That surfaced during `superpowers:finishing-a-development-branch`: after a
feature branch was ready to merge locally, the workflow tried to update `main`
first, but the hook rejected the pull as a primary-worktree write.

The policy intent is different. `codex/.codex/AGENTS.md` already treats
ordinary GitHub-scoped `git pull` as an allowed branch sync operation. For this
repo, `origin` is the source of truth, so pulling the latest state into the
local primary checkout should be allowed without weakening protections against
arbitrary primary-checkout edits.

## Goals

- Allow safe `git pull` usage in the primary checkout.
- Keep the worktree guard strict for unrelated primary-checkout writes.
- Reject broad or ambiguous pull forms that can update unrelated refs or target
  unrelated branches.
- Cover the behavior with focused hook tests.

## Non-Goals

- Do not allow force-like, all-remote, tag-sync, or arbitrary refspec pull
  forms.
- Do not change push, merge, branch deletion, or worktree cleanup policy.
- Do not make `git pull` a read-only command; it writes the checkout and should
  remain a narrowly allowed sync operation.

## Recommended Approach

Add a narrow helper in `codex/.codex/hooks/worktree-guard.sh`, likely named
`is_allowed_primary_checkout_pull_command`.

The helper should accept only simple current-branch sync forms:

- `git pull`
- `git pull origin`
- `git pull origin <current-branch>`
- `git pull --ff-only`
- `git pull --rebase`
- safe combinations where `--ff-only` or `--rebase` appear before the optional
  `origin` and current branch

The helper should reject:

- shell control syntax
- path indirection or command substitution
- `--force`, `--all`, `--tags`, `--prune`, and other broad fetch/pull flags
- explicit branch names other than the active branch
- extra positional arguments
- explicit remotes other than `origin`

Call this helper before the generic primary-worktree approval requirement for
shell and MCP executor commands. It should apply only when the command is being
evaluated for the current repository's primary checkout. Linked worktree
behavior should remain unchanged unless the command naturally targets that
worktree and already passes existing rules.

## Error Handling

Rejected pull forms should continue through the existing guard path and require
approval or denial based on their target. There is no new user-facing error
format; the hook's existing primary-worktree approval message remains the
fallback.

## Testing

Extend `codex/.codex/tests/test-worktree-guard-hook.sh` with focused cases:

- plain `git pull` from the primary checkout is allowed
- `git pull --ff-only` is allowed
- `git pull --rebase` is allowed
- `git pull origin <active-branch>` is allowed
- `git pull origin other-branch` is blocked
- `git pull --all` is blocked
- `git pull --tags` is blocked
- `git pull --force` is blocked
- a pull command with shell control syntax is blocked or still requires
  approval through existing guard behavior

Run the hook test suite after implementation. If there is no broader test suite
for this repo, this hook test is the required verification.
