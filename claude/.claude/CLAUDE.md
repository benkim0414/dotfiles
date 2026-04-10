# Global Claude Code Preferences

## Claude Code Workflow
- Editor: nvim
- Never use emojis in responses
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
- When implementation is complete: run `/create-pr` to review and create the PR.
  Push with an explicit refspec (`git push origin HEAD:<branch>`) to avoid
  `push.default=upstream` redirecting to main. Stay in the worktree after PR creation.
- When the PR is approved: `ExitWorktree("keep")` to return to main.
  Use `ExitWorktree("remove")` only to discard exploratory work with no commits.
- After ExitWorktree: wait for the user to merge. Do NOT run `gh pr merge` proactively.
- After merge: `/merge-pr` handles finalization (update main, remove worktree, delete branch).
- To resume an open PR: start Claude Code from within the worktree directory.

## Hook Architecture

Seven hooks enforce workflow guardrails (git guards, worktree isolation,
notifications, audit logging). If blocked, read the stderr message. Emergency
worktree escape: `rm ~/.claude/session-worktrees/pending-<session-id>`.

## Git Discipline
- Conventional commits: `type(scope): description` -- types: feat, fix, docs, chore, refactor, test, ci, perf
- Write a commit body when the why is not obvious from the title
- Review diffs for accidental secrets before every commit
- Always use merge commits (`gh pr merge --merge`), never squash or rebase -- preserve full commit history

## Security

Never hardcode secrets in version-controlled files. Rotate immediately after exposure.
Audit third-party tools/scripts before running them.

## Domain Rules

DevOps rules (K8s, Docker, GHA, Terraform, Helm, shell) are in
`~/.claude/includes/devops.md`. Add `@includes/devops.md` to project-level
CLAUDE.md files in repos that need them.
