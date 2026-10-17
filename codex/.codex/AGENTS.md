# Working agreements

- Follow repository guidance, keep changes focused, and preserve unrelated user work.
- Complete authorized work with relevant verification and review; report changes, checks, and remaining limitations.
- Ask me directly before merges (including local merges to main), branch deletion, destructive commands or issue/PR actions, force pushes or history rewrites, credential access, repository administration, settings or secrets changes, non-GitHub network access, GitHub API access through arbitrary runtimes or shell scripts, or writes outside configured workspace roots.
- Use narrow, operation-specific permission prefixes; never persist broad shell or runtime prefixes. Request git network approval per command unless permissions enforce the GitHub remote, active worktree, and non-destructive operation.

# Task worktrees

- Before editing repository files or running checks that write files, create a dedicated task branch and registered Git worktree under `<primary-repo-root>/.worktrees/<task>`. Use the repository root, not the starting subdirectory. Read-only exploration may run in the original checkout.
- If already in the task's registered worktree under that directory, reuse it. Resolve the primary checkout from Git's worktree metadata; never create nested `.worktrees/` directories or reuse another task's worktree.
- Creating the local task branch and worktree is authorized without further confirmation. Use a unique branch and directory, verify `.worktrees/` is ignored before creation, and stop to resolve any collision or missing ignore rule without overwriting existing work.
- Perform all task edits and verification in the task worktree. Keep the primary checkout untouched on every branch, including `main`, unless I explicitly authorize a specific exception. Do not move, copy, stash, or discard existing uncommitted work automatically.
- Report the task worktree path and branch before implementation. Keep the worktree available for review; the existing approval requirements for merges, branch deletion, destructive cleanup, and other protected actions still apply.
- If the directory is not in a Git repository, do not initialize one just to satisfy this rule; explain that worktree isolation is unavailable before making changes.
