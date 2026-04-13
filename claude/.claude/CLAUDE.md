# Global Claude Code Preferences

## Preferences
- Editor: nvim
- Never use emojis in responses
- IMPORTANT: Never assume -- if requirements are ambiguous, underspecified, or open to multiple interpretations, ask clarifying questions before proceeding. This applies to task scope, implementation approach, edge cases, naming, and any decision that could go more than one way.
- Use the fetch MCP to look up current docs, API versions, or package versions -- training data goes stale; never guess at versions
- Explain the reasoning behind config choices, not just what to set
- Present the dry-run/plan/diff form of a command before the apply form; let the user review first

## Git Workflow

All work happens on isolated worktree branches. Hooks enforce worktree isolation,
main-branch protection, and selective staging -- follow the `[git-workflow]` context
injection at session start.

- "MODE: no-pr": after committing, `ExitWorktree("keep")`, merge to main, push. No PRs.
- Commit each self-contained logical change atomically.
- Conventional commits: `type(scope): description` -- types: feat, fix, docs, chore, refactor, test, ci, perf
- When implementation is complete: `/create-pr` to review and create the PR.
  Push with explicit refspec (`git push origin HEAD:<branch>`) to avoid `push.default=upstream` redirecting to main.
- When PR is approved: `ExitWorktree("keep")` to return to main.
  Use `ExitWorktree("remove")` only to discard exploratory work with no commits.
- After ExitWorktree: wait for the user to merge. Do NOT run `gh pr merge` proactively.
- After merge: `/merge-pr` handles finalization.
- YOU MUST use merge commits (`gh pr merge --merge`), never squash or rebase.
