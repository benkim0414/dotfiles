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

All work happens on isolated worktree branches. Hooks enforce worktree isolation,
main-branch protection, and selective staging -- follow the `[git-workflow]` context
injection at session start.

- "MODE: no-pr": after committing, `ExitWorktree("keep")`, merge to main, push. No PRs.
- Commit each self-contained logical change atomically with a conventional message.
- When implementation is complete: run `/review-cl` to self-review and create the PR.
  Push with an explicit refspec (`git push origin HEAD:<branch>`) to avoid
  `push.default=upstream` redirecting to main. Stay in the worktree after PR creation.
- When the PR is approved: `ExitWorktree("keep")` to return to main.
  Use `ExitWorktree("remove")` only to discard exploratory work with no commits.
- After ExitWorktree: wait for the user to merge. Do NOT run `gh pr merge` proactively.
- After merge: `/merge-pr` handles finalization (update main, remove worktree, delete branch).
- To resume an open PR: start Claude Code from within the worktree directory.

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
