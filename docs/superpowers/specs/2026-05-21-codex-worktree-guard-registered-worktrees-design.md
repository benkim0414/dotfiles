# Codex Worktree Guard Registered Worktrees Design

## Context

The live guard test showed that writes inside the registered linked worktree
`/home/benkim0414/workspace/dotfiles/.worktrees/tmux-blink-ipad-clipboard`
were blocked. Direct `apply_patch`, shell `apply_patch`, and `git apply`
attempts all resolved to the primary checkout and produced the primary-worktree
approval message. Writes to the primary checkout and to an unregistered
`.worktrees/plain-dir` path were also blocked.

The guard needs to protect the primary checkout while allowing normal work
inside any Git-registered linked worktree.

## Goals

- Allow write-capable operations inside any registered linked worktree reported
  by `git worktree list --porcelain`.
- Keep write-capable operations targeting the primary checkout behind explicit
  approval.
- Ensure a plain directory under `.worktrees/` is not trusted unless Git reports
  it as a registered worktree.
- Cover direct `apply_patch`, shell `apply_patch`, and `git apply` because all
  three failed in the live test.
- Preserve existing guard behavior for paths outside the repository and its
  registered worktrees unless a regression test proves it needs adjustment.

## Non-Goals

- Do not trust paths merely because they are under `.worktrees/`.
- Do not broaden approval for writes to the primary checkout.
- Do not redesign unrelated hook policies such as commit-scope validation.

## Worktree Registry

The guard will parse `git worktree list --porcelain` and treat the first
`worktree` entry as the primary checkout. Every later `worktree` entry is a
registered linked worktree. Registered linked worktrees are trusted regardless of
where they live, including project-local `.worktrees/`, sibling directories, and
temporary directories.

All registry paths and candidate target paths will be realpath-normalized before
comparison.

## Target Classification

Classification uses longest-prefix matching against the normalized worktree
registry. Registered worktrees are checked before the primary checkout so nested
worktree paths such as:

`/home/benkim0414/workspace/dotfiles/.worktrees/tmux-blink-ipad-clipboard`

match the linked worktree rather than the primary checkout.

Classification outcomes:

- `registered-linked-worktree`: allow write-capable operations.
- `primary-worktree`: require explicit approval.
- `unregistered-worktree-like-path`: require explicit approval when the path is
  under the repository `.worktrees/` directory but is not in the Git worktree
  registry.
- `outside-known-worktrees`: keep the existing policy.

## Tool Handling

Direct `apply_patch` classification will inspect every file path in the patch.
Relative patch paths are resolved against the tool workdir. Absolute patch paths
are classified directly.

Shell `apply_patch` and `git apply` classification will include the command's
effective workdir as a target. When the command text includes patch headers, the
guard will also classify patch paths from those headers to catch absolute paths
and `../` escapes.

The command workdir and patch paths must be considered together. A command whose
workdir is a registered linked worktree must not be reclassified as primary
only because Git's common directory is stored under the primary checkout.

## Guard Messages

Primary checkout denials keep the existing wording:

`Codex worktree guard detected primary worktree targeting <path>; this requires explicit approval.`

Unregistered worktree-like paths use a distinct message:

`Codex worktree guard detected unregistered worktree-like path <path>; this requires explicit approval.`

Allowed registered linked-worktree writes do not emit a denial message.

## Regression Tests

Add automated coverage for:

- direct `apply_patch` absolute path inside a registered linked worktree is
  allowed
- shell `apply_patch` with workdir inside a registered linked worktree is allowed
- `git apply` with workdir inside a registered linked worktree is allowed
- direct write to the primary checkout still requires approval
- write to `.worktrees/plain-dir` is not trusted
- longest-prefix matching favors a registered linked worktree nested under the
  primary checkout over the primary checkout itself
- a registered linked worktree outside `.worktrees/` is trusted

## Live Verification

After implementation, rerun the live probes with throwaway files:

1. Direct `apply_patch` into
   `.worktrees/tmux-blink-ipad-clipboard/.codex-guard-direct-apply-patch-test`.
2. Shell `apply_patch` with workdir set to the linked worktree.
3. `git apply` with workdir set to the linked worktree.
4. Direct write targeting `/home/benkim0414/workspace/dotfiles`.
5. Direct write targeting `.worktrees/plain-dir`.

Successful linked-worktree probes must create files and then remove them.
Blocked probes must not create files and must report the expected guard message.

Also run the hook's automated test command or the closest available test suite
for the guard.
