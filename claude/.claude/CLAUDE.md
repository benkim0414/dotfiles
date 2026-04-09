# Global Claude Code Preferences

## Claude Code Workflow
- Editor: nvim
- Never use emojis in responses
- Always invoke sequential-thinking MCP before implementing non-trivial changes
- Use the fetch MCP to look up current docs, API versions, chart versions, or image digests -- training data goes stale; never guess at versions
- Explain the reasoning behind config choices, not just what to set
- Before any state-changing command, state what resources will be affected and the blast radius
- Present the dry-run/plan/diff form of a command before the apply form; let the user review first

## Git Session Workflow
- At session start, check the `[git-workflow]` context injection.
- If it says "WORKTREE REQUIRED": call `EnterWorktree()` as the absolute first action --
  before any Write, Edit, Bash, or notebook edit. The hook blocks file-editing tools until you do.
  Pass no argument; Claude Code auto-generates an isolated branch off HEAD.
- If it says "Worktree session active": already isolated (started with `--worktree` or
  a prior `EnterWorktree()` call); proceed directly with the task.
- If the context includes "MODE: no-pr": use worktrees for isolation, but after
  committing on the branch, ExitWorktree("keep"), merge the branch to main
  (`git merge <branch> --no-edit`), and push (`git push origin main`).
  Do not create PRs or run `/review-cl`.
- After each self-contained logical change (not per-file, per-logical-unit): stage only the
  relevant files, commit with a conventional message, then proceed to the next change.
- Do not batch multiple unrelated changes into a single commit.
- When initial implementation is complete: run `/review-cl` to self-review all changes,
  fix issues iteratively, and create the PR. This starts a Ralph Loop that diffs against
  main, reviews every changed file, commits fixes, and only creates the PR when the review
  is clean. Always push with an explicit refspec (`git push origin HEAD:<branch>`) to avoid
  `push.default=upstream` redirecting to main. Stay in the worktree after the PR is created
  -- do NOT call ExitWorktree yet.
  Address any review feedback with additional commits in the same worktree, then re-push.
- When the PR is approved and ready to merge: call `ExitWorktree("keep")` to return to main.
  Use `ExitWorktree("remove")` only to discard exploratory work with no commits worth keeping.
- After ExitWorktree: wait for the user to merge the PR on GitHub.
  Do NOT merge without explicit user approval. Do NOT run `gh pr merge` proactively.
- After the user merges the PR (or when the user runs `/merge-pr`): the merge-pr command
  handles full finalization -- updates local main, removes the worktree, and deletes the
  local branch. If the user merged via GitHub UI without `/merge-pr`, run `git pull`,
  then `git worktree remove <path>` and `git branch -d <branch>` to clean up manually.
- To resume PR review in a new session: start Claude Code from within the worktree directory
  (e.g. `claude` from `.claude/worktrees/<name>/` -- paths listed at session start);
  the session-start hook detects the linked worktree and skips the EnterWorktree requirement.
- Never commit or push directly to main -- the guard hook will block it --
  unless the session context includes "MODE: no-pr" (merge + push allowed).

## Git Discipline
- Conventional commits: `type(scope): description` -- types: feat, fix, docs, chore, refactor, test, ci, perf
- Atomic commits: one logical change per commit; keep unrelated changes separate
- Write a commit body when the why is not obvious from the title
- Branch workflow: feature branches off main, open PR
- Never force-push to main or shared branches
- Review diffs for accidental secrets before every commit
- Always use merge commits (`gh pr merge --merge`), never squash or rebase -- preserve full commit history

## Security
- Never hardcode secrets, tokens, or credentials in version-controlled files
- Rotate secrets immediately after accidental exposure; deleting commits is insufficient
- Least privilege: grant only the permissions actually needed
- Prefer dedicated secret management tools over environment variables or config files
- Audit new tool installations and third-party scripts before running them

## Domain Rules
@includes/devops.md
