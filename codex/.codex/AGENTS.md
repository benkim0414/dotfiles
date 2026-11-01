# Task workflow

- Follow repository guidance and keep changes focused. Preserve pre-existing user work; do not move, copy, stash, overwrite, or discard it without approval.
- Before edits or checks that write files, create a dedicated task branch and registered worktree under `<primary-repo-root>/.worktrees/<task>`, or reuse this task's existing worktree there. Resolve the primary checkout from Git's worktree metadata; never nest `.worktrees/` directories or reuse another task's worktree.
- Worktree and task-branch creation are authorized. Choose unique names without overwriting existing work.
- Verify `.worktrees/` is ignored before creating a worktree. If needed, add only `/.worktrees/` to the repository-local Git exclude file, preserving existing entries, and verify the exclusion.
- Read applicable instructions after switching worktrees. Report the branch and path before implementation, and perform all edits and verification there. Read-only exploration may use the original checkout.
- Proceed without asking for reversible, task-related file creation, edits, renames, deletions, formatting, builds, tests, and generated-file cleanup. This includes versioned configuration and dependency files.
- Local commits, merges into the task branch, and amendments, rebases, or resets of its unpublished history are authorized.
- Roll back your own changes and remove your own disposable artifacts as needed.
- Before operations that could lose non-reproducible work, ensure affected content is recoverable from a commit or a backup within the task worktree. Checkpoint uncommitted and untracked content when needed; worktrees and reflogs alone do not preserve it.
- Complete authorized work with relevant verification and review. Report changes, checks, and remaining limitations.
- Retain the task branch and worktree for review.
- Outside a Git repository, explain that worktree isolation is unavailable before making changes. Do not initialize a repository just to satisfy this workflow.

# When to ask for approval

Judge actions by their effects: worktrees share Git metadata and do not isolate external systems. Editing versioned configuration is local work; applying it to live settings or services requires approval.

Except for operations explicitly authorized above or by a request or approval in this conversation, ask me directly before:

- Changing the primary checkout, other worktrees or branches, or published history; deleting branches or worktrees; or destructive actions without assured recovery.
- Remote mutations, including pushes, force pushes, and issue/PR actions.
- Credential access, repository administration, live settings or services changes, secrets changes, or writes outside configured workspace roots.
- Non-GitHub network access or GitHub API access through arbitrary runtimes or shell scripts.

Keep authorization scoped to the specified action; do not ask again for an already authorized action.

Use narrow, operation-specific permission prefixes; never persist broad shell or runtime prefixes.

Request git network approval per command unless permissions enforce the GitHub remote, active worktree, and non-destructive operation.
