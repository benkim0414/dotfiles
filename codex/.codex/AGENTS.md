# Working agreements

Follow applicable repository guidance and keep changes focused. The approval requirements below take precedence over every standing permission in this file. An explicit user request or approval can authorize the specific action it covers.

## Task worktree

- Preserve pre-existing user work. Do not move, copy, stash, overwrite, or discard it without approval.
- Before edits or checks that write files, create a dedicated task branch and registered worktree at `<primary-repo-root>/.worktrees/<task>`, or reuse this task's existing worktree there. Resolve the primary checkout from Git worktree metadata. Never nest `.worktrees/` directories or reuse another task's worktree.
- Branch and worktree creation are authorized. Choose unique names. Verify `.worktrees/` is ignored first; if needed, append only `/.worktrees/` to the repository-local Git exclude file, preserve existing entries, and verify the exclusion.
- After switching, read applicable instructions and report the branch and path before implementation. Perform edits and verification there; read-only exploration may use the original checkout.
- Local commits, merges into the task branch, and amendments, rebases, or resets of its unpublished history are authorized. You may roll back your own changes and clean up your own disposable artifacts.
- Before any operation that could lose non-reproducible work, preserve affected content in a commit or backup within the task worktree. Include uncommitted and untracked content when needed; worktrees and reflogs alone do not preserve it.
- Complete the requested work with relevant verification and review. Report changes, checks, and limitations. Retain the branch and worktree for review.
- Outside Git, explain that worktree isolation is unavailable before making changes. Do not initialize a repository just to satisfy this workflow.

## Local development

- Proceed without asking for reversible, task-related file changes, formatting, builds, tests, code generation, local development servers, and generated-file cleanup. Versioned configuration and dependency files are included.
- Allow project-local dependency installs and downloads from package registries. Development commands may write within the task worktree and the package manager's normal cache or store.
- Before running a package-manager script, read its definition and the project scripts it invokes. Permission covers only the inspected script names and effects. Inspect install lifecycle scripts too; disable uninspected hooks or ask before running them.
- Judge scripts and hooks by their effects. A familiar command name or worktree location does not authorize deployment, publishing, live-service changes, credential use, unrelated network activity, or other external writes.

## GitHub operations

These permissions apply only to the current task's repository and remain subject to the approval requirements below.

| Tool | Allowed operations |
| --- | --- |
| `gh pr` | `view`, `list`, `create`, `edit`, `comment`, `checks`, `status` |
| `gh issue` | `view`, `list`, `create`, `edit`, `comment`, `status` |

- Edits and comments must concern issues or PRs created by this task or explicitly included in the user's requested work.
- The allow-list excludes approving, submitting or requesting reviews, including reviewer requests through `create` or `edit`. Closing, merging, releasing, dispatching workflows, and `gh api` also require approval.
- Allow GitHub fetches from an existing remote, issued from the task worktree, without pruning or changing local branches or tags.
- Allow only a non-force, fast-forward push from the current task worktree of the current task branch to the same branch ref on its existing GitHub upstream. This may extend that task branch, but must not rewrite published history, update a shared branch, or use a remote whose push deploys.
- Push permission excludes `--force`, `--force-with-lease`, deletion refspecs, `--tags`, `--all`, `--mirror`, other remotes, and other refs. Pushes outside these limits require approval.

## Ask before proceeding

Unless the user has explicitly requested or approved the specific action, ask before:

- Changing the primary checkout, other worktrees or branches, rewriting published history, updating shared branches, or deleting branches or worktrees.
- Destructive local actions without assured recovery; destructive remote actions, including force pushes and deletion of remote resources.
- PR merges or enabling auto-merge, and GitHub operations outside the allow-list and bounded fetch/push permissions above.
- Credential access or use, authentication changes, or secrets changes. The sole credential exception is Git and `gh` using credentials already configured for the current repository for an otherwise authorized operation, without printing, copying, extracting, or changing them. Other uses of environment tokens, cloud CLI credentials, and SSH keys require approval.
- Repository administration, security settings, live settings or services changes, deployments, or package publishing, including through scripts or `gh`. Editing versioned configuration is local work; applying it to a live service requires approval.
- Global or system installs, such as `npm install -g`, `cargo install`, or `brew install`, and writes outside the task worktree. The only write exceptions are the worktree/Git metadata operations authorized above and the package manager's normal cache or store.
- Network activity outside the development and GitHub permissions above, including GitHub API access through arbitrary runtimes or shell scripts.

## Approval enforcement

- Treat each authorized action as standing approval for that action and retries of the same action within the same limits. Do not ask again for an already authorized action. Keep additional approvals scoped to the specific action.
- Respect sandbox and tool permission enforcement. Run authorized commands with available permissions. If enforcement requires escalation, use its approval mechanism without an additional conversational confirmation. Do not bypass enforcement or change sandbox or approval settings to avoid a prompt.
- Use narrow, operation-specific permission prefixes. Never persist broad shell or runtime prefixes.
- Do not save durable `git fetch` or `git push` prefixes unless enforcement pins the exact GitHub remote, current task worktree, allowed refs, and non-destructive, non-deploying operation. Otherwise, each command must go through the approval mechanism without a saved prefix. Bare `git fetch` and `git push` prefixes cannot enforce these limits.
- A saved package-manager script prefix must include the inspected script name, such as `npm run test`, and must not permit uninspected arguments or effects. Never save `npm` or `npm run` alone. Do not save install prefixes such as `npm install` that also allow global installs or uninspected lifecycle hooks; use per-command approval when those limits cannot be enforced.
- Do not save `gh` prefixes that permit other repositories or excluded flags and effects.
