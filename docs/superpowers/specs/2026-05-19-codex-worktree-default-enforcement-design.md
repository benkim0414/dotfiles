# Codex Worktree Default Enforcement Design

## Context

This dotfiles repo uses both Superpowers and Compound Engineering workflows. The intended flow for non-trivial changes is:

```text
brainstorming -> writing-plans -> subagent-driven-development -> requesting-code-review -> ce-compound
```

Those skills create artifacts as part of the work: brainstorming writes specs under `docs/superpowers/specs/`, writing-plans writes plans under `docs/superpowers/plans/`, and `ce-compound` writes solution docs under `docs/solutions/`. These artifacts should live on the same feature branch as the implementation, not appear directly on `main`.

Claude already has a worktree-oriented workflow in this repo, but Codex needs a Codex-native enforcement mechanism. Codex should not copy Claude's `EnterWorktree` flow. It should enforce the invariant at the Codex hook boundary, using the hook payload and Git metadata available to Codex.

## Goal

Make linked Git worktrees the default for any Codex-driven change in any Git repository. If Codex starts in a repository's main worktree and attempts to write repo files, the hook blocks the write and tells Codex exactly how to create and enter a linked worktree.

## Non-Goals

- Do not silently create worktrees from the hook.
- Do not hard-code the dotfiles repository path.
- Do not enforce worktrees outside Git repositories.
- Do not merge or clean up worktrees automatically.
- Do not weaken the existing atomic commit hook.
- Do not rely on path naming to decide whether a checkout is a linked worktree.

## Recommended Approach

Add a dedicated global Codex `PreToolUse` hook, separate from `atomic-commits.sh`.

The hook runs for write-capable tools and blocks repo-file writes when the tool call is executing from the main worktree of any Git repository. It allows the call when:

- the `cwd` is not inside a Git worktree,
- the `cwd` is inside a linked Git worktree,
- the tool call is read-only,
- the target is outside the current Git worktree, or
- the target is explicitly allowlisted for guard maintenance.

The guard should fail closed for main-worktree repo writes and print an operational recovery message:

```bash
git worktree add .worktrees/<slug> -b <branch>
cd .worktrees/<slug>
```

The `.worktrees/<slug>` convention is the default because it keeps feature checkouts discoverable from the project root. The hook should recommend that path relative to whichever repository Codex is currently operating in.

## Worktree Detection

Detect linked worktrees using Git metadata:

1. Run `git rev-parse --show-toplevel` from the hook `cwd`.
2. Run `git rev-parse --absolute-git-dir`.
3. Run `git rev-parse --git-common-dir` and resolve it relative to `cwd` when Git returns a relative path.
4. Treat the checkout as a linked worktree when the resolved absolute Git dir differs from the resolved common Git dir.

This avoids path assumptions and works for any repository. It also matches Git's model: a linked worktree has per-worktree Git metadata while sharing the common repository storage.

The implementation should account for submodules. In a submodule, Git metadata can also differ from the parent repository. The guard should treat the submodule as its own repository and apply the same main-vs-linked worktree decision to that repository, not to the parent checkout.

## Hook Scope

Configure the hook in `codex/.codex/config.base.toml` so synced Codex installations get the behavior globally.

The matcher should cover write-capable Codex tools:

- `apply_patch`
- `Edit`
- `Write`
- shell command tools that can write files
- MCP tools that can create or modify files, where the tool name exposes that intent

The shell-script guard should parse the Codex hook JSON payload. It should use `cwd` as the repo context and inspect tool-specific input fields to decide whether the attempted target is inside the current repository.

For shell commands, the first implementation can be conservative: if the command tool runs from a main worktree and is not clearly read-only, block with the worktree recovery message. Read-only shell commands such as `git status`, `git diff`, `rg`, `sed -n`, and `ls` should remain usable from the main checkout so Codex can inspect before creating a worktree.

## User-Facing Behavior

When blocked, Codex should see a concise message that explains:

- changes and generated artifacts must be made from a linked worktree,
- the current checkout is the repository's main worktree,
- examples of protected artifacts include Superpowers specs, Superpowers plans, Compound solution docs, and normal code/config files,
- the exact commands to create and enter a worktree.

Example message:

```text
Codex worktree guard blocked this write because the current directory is the repository's main worktree.

Create a linked worktree and continue there:
  git worktree add .worktrees/<slug> -b <branch>
  cd .worktrees/<slug>

All repo changes and generated artifacts, including docs/superpowers/specs/, docs/superpowers/plans/, docs/solutions/, code, and config files, belong in the feature worktree.
```

The message may suggest a slug derived from the current prompt or branch when that data is available. Otherwise it should use placeholders rather than inventing a misleading branch name.

## Components

- `codex/.codex/hooks/worktree-guard.sh`
  - New Bash hook.
  - Reads Codex hook JSON from stdin.
  - Resolves `cwd`, repo root, Git dir, and common Git dir.
  - Determines whether the current checkout is a linked worktree.
  - Classifies the tool call as write-capable or read-only.
  - Blocks repo writes from main worktrees with exit code `2`.

- `codex/.codex/config.base.toml`
  - Adds a `PreToolUse` hook entry for the new guard.
  - Keeps the existing atomic commit hook unchanged.

- `codex/.codex/tests/test-worktree-guard-hook.sh`
  - Adds focused hook tests for non-repo directories, main worktrees, linked worktrees, external paths, read-only commands, and write-capable commands.

- `codex/.codex/tests/test-codex-sync-hooks.sh`
  - Verifies the new hook is synced and executable alongside existing hooks.

- `codex/.codex/AGENTS.md`
  - Documents that Codex changes in Git repositories must happen from linked worktrees.
  - Notes that generated workflow artifacts are part of the feature branch.

## Testing

Tests should use temporary repositories rather than this checkout:

1. Non-Git directory allows write-capable tool calls.
2. Main worktree blocks `apply_patch` or `Write` targeting a repo file.
3. Main worktree allows write-capable tool calls targeting paths outside the repo.
4. Linked worktree allows repo-file writes.
5. Main worktree allows clearly read-only shell commands.
6. Main worktree blocks ambiguous or write-capable shell commands.
7. Hook message includes `.worktrees/<slug>` recovery guidance.
8. Sync tests install `worktree-guard.sh` with executable permissions.

Run the new test file directly and then the existing Codex hook tests:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
bash codex/.codex/tests/test-atomic-commits-hook.sh
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

## Error Handling

If Git commands fail because the directory is not a Git repo, allow the call.

If Git commands fail inside what appears to be a Git repo, block only when the target is inside the repo and the operation is write-capable. The message should say the guard could not verify linked-worktree status and give the same recovery command.

If the hook receives malformed JSON, block write-capable-looking calls only when a safe `cwd` can be recovered. Otherwise allow and print a diagnostic to stderr so Codex does not get trapped by a broken hook payload.

## Open Questions Resolved

- Worktree directory convention: `.worktrees/<slug>` under the current repository root.
- Hook behavior when starting from main: block and provide recovery commands; do not auto-create.
- Enforcement scope: any Git repository, not just dotfiles.
- Artifact scope: all repo changes and generated artifacts, including Superpowers specs/plans and Compound solution docs.
