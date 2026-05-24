# Codex User Instructions

## Subagent Approval Contract

- Subagents inherit durable Codex config from `$CODEX_HOME/config.toml`.
- Keep `approval_policy = "on-request"`; do not bypass the sandbox globally.
- Routine sandbox-compatible repository work should flow through the configured auto reviewer.
- GitHub-scoped collaboration and branch sync operations may flow through auto-review when issued from an active repository worktree.
- Allowed GitHub operations include PR `view/list/create/edit/comment/check/status/review`, issue `view/list/create/edit/comment/status`, `git fetch`, `git pull`, and ordinary non-force current-branch `git push` to GitHub remotes.
- Sensitive operations require direct user approval and must not be approved by auto-review: `gh pr merge`, GitHub merge operations, local merge-to-main operations such as `git checkout main` followed by `git merge <branch>`, branch deletion, repository administration, settings or secrets changes, destructive issue or PR operations, force pushes, history rewrites, credential access, non-GitHub network access, direct GitHub API access through arbitrary runtimes or shell scripts, destructive commands, and writes outside configured workspace roots.
- Persistent prefix rules must be narrow and command-specific, with operation-specific examples such as `gh pr view`, `gh pr list`, `gh pr create`, `gh pr edit`, `gh pr comment`, `gh pr check`, `gh pr status`, `gh pr review`, `gh issue view`, `gh issue list`, `gh issue create`, `gh issue edit`, `gh issue comment`, and `gh issue status`.
- Under the current prefix-rule model, git network commands (`git fetch`, `git pull`, `git push`) should use per-command approval unless the approval mechanism can enforce the exact GitHub, active-worktree, and non-destructive constraints.
- Do not persist broad runtime prefixes such as `bash`, `python`, `node`, `ruby`, `perl`, or `sh`.

## Standing Worktree Approvals

- Creating a linked worktree through `superpowers:using-git-worktrees` is standing user-approved for feature/change work when the current checkout is not already a linked worktree.
- When `superpowers:brainstorming` may lead to repo edits, ensure a linked worktree exists before writing specs, plans, docs, or code.
- Preserve the repository-local convention `git worktree add .worktrees/<slug> -b <branch>` and continue from `.worktrees/<slug>`.
- `finishing-a-development-branch` option 4 discard cleanup is standing user-approved only after the user has selected discard, and only for removing the confirmed isolated feature worktree/branch.
- Explicit user approval is still required for local merge-to-main, push/PR operations outside the existing auto-review allowance, force operations, writes outside configured workspace roots, unrelated branch/worktree deletion, uncommitted changes, and unmerged user work that was not explicitly abandoned.

## Default Implementation Workflow

- When a Superpowers implementation plan is ready to execute, always use `superpowers:subagent-driven-development`.
- Do not offer `superpowers:executing-plans`, inline execution, or a choice between subagents and the main agent unless the user explicitly asks for an alternative or subagents are unavailable.
- If a loaded plugin skill suggests asking the user to choose an execution mode, treat this standing instruction as the user's preselection of subagent-driven development.

## Worktree Isolation

- For any change in a Git repository, work from a linked Git worktree rather than the repository's main worktree.
- Use the repository-local convention `git worktree add .worktrees/<slug> -b <branch>` and continue from `.worktrees/<slug>`.
- Generated workflow artifacts are part of the feature branch. This includes Superpowers specs in `docs/superpowers/specs/`, Superpowers plans in `docs/superpowers/plans/`, Compound solution docs in `docs/solutions/`, and normal code or config changes.
- A Codex PreToolUse hook enforces this for repo writes. If it blocks a write, create a linked worktree using the hook's suggested command, or enter the appropriate existing linked worktree.

## Git Commit Workflow

- Commit each self-contained logical change separately.
- Use conventional commit subjects: `type(scope): description`.
- Prefer these types unless the project documents a different convention:
  `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, and `perf`.
- Stage explicit paths only. Do not use `git add -A`, `git add --all`,
  `git add -u`, `git add .`, `git commit -a`, or `git commit -am`.
- Before committing, inspect `git diff` and `git diff --cached`.
- If the working tree contains unrelated edits, split them into separate
  commits by staging only the files for one logical change at a time.
- Choose commit scopes from recent project history when a clear scope exists.
  A new scope is acceptable when the project genuinely needs one.
- For generated or planning documentation, choose the scope from the component,
  product area, or domain described by the staged content. Do not infer scope
  from the document format, workflow name, generator name, or directory name
  unless that system is genuinely what the commit changes.
  Prefer `docs(<affected-component>): describe <change>` over
  `docs(<artifact-or-generator-name>): describe <change>`. If the change is
  repo-wide and no component dominates, omit the scope.
- Keep the commit subject concise. Aim for 72 characters or fewer.
- Run relevant verification before committing when feasible. If no verification
  command is obvious, say that explicitly.
- Use Codex `/review` before finalizing non-trivial changes.
- If a commit message hook rejects a subject, read the rejection reason, inspect
  recent subjects with `git log --format=%s -50`, and retry with a valid
  conventional subject.
