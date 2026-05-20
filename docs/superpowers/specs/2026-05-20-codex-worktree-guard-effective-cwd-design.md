# Codex Worktree Guard Effective Cwd Design

## Context

The Codex worktree guard was added to prevent repository writes from a main
worktree and require feature work in linked Git worktrees. The guard currently
trusts the hook payload's `cwd` as the command execution directory.

Another Codex session created the expected linked worktree at
`/home/benkim0414/workspace/allegro/.worktrees/issue-13-token-bootstrap`, made
only documentation changes, and passed verification and review. It was still
blocked from staging and committing because the guard reported that the current
directory was the repository's main worktree. The blocked commands included
normal linked-worktree Git operations such as `git add README.md
docs/github-issues.md`, lower-level staging attempts, and unrelated scratch
writes such as `touch /tmp/...`.

The failure suggests the hook may receive the session or repository root as
`cwd` even when the shell tool is invoked with an effective `workdir` inside a
linked worktree.

## Goal

Keep the main-worktree protection intact while allowing legitimate write-like
operations when the effective execution target is a linked worktree or a
non-repository scratch directory.

## Non-Goals

- Do not weaken protection for writes into a repository's main worktree.
- Do not allow ambiguous shell commands that can redirect or mutate files in a
  main worktree.
- Do not change the atomic commit hook.
- Do not bypass Codex approval or sandbox policy.
- Do not make the hook create, stage, commit, or merge work automatically.

## Design

The guard should distinguish the hook session directory from the command's
effective execution directory.

For shell-style tools, the guard should prefer an explicit tool workdir when
Codex provides one in the hook payload. If no effective workdir is available,
it should continue to use the current `cwd` behavior.

The guard should also understand explicit Git directory selection:

- `git -C <linked-worktree> add README.md docs/github-issues.md` is allowed
  because the Git command executes against a linked worktree.
- `git -C <main-worktree> add README.md` remains denied.
- Read-only `git -C <main-worktree> status`, `diff`, `log`, and similar
  inspection commands remain allowed.

Shell commands that clearly target files outside any Git repository, including
scratch paths under `/tmp`, should be allowed. The worktree guard protects Git
repository worktrees; it should not block unrelated temporary-file operations
only because the Codex session started from a main checkout.

Path-targeted direct write tools should keep their existing target-path based
behavior: writes into linked worktrees are allowed, writes into main worktrees
are denied, and writes outside Git repositories are allowed.

## Error Handling

If Git metadata cannot be resolved for a path inside a repository-like
directory, the guard should fail closed only for operations that appear to
target repo files. The denial message should keep the existing recovery
guidance for creating and entering a linked `.worktrees/<slug>` checkout.

If the hook payload does not include an effective workdir field, the guard
should preserve current behavior rather than guessing from directory names.

## Testing

Add focused tests in `codex/.codex/tests/test-worktree-guard-hook.sh` covering:

- A shell command whose hook `cwd` is the primary worktree but whose effective
  workdir is a linked worktree is allowed for `git add README.md`.
- `git -C <linked-worktree> add README.md docs/github-issues.md` is allowed
  from a primary-worktree hook `cwd`.
- `git -C <primary-worktree> add README.md` is denied from any cwd.
- `touch /tmp/<file>` is allowed from a primary-worktree hook `cwd`.
- Existing denials for writes from a linked worktree back into the primary
  worktree still pass.

Run:

```sh
bash codex/.codex/tests/test-worktree-guard-hook.sh
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

## Rollout

Implement the hook and test changes in a linked worktree, regenerate or verify
the synced Codex config only if the hook installation path changes, then commit
the fix on the feature branch. The fix is local to the guard script and tests.
