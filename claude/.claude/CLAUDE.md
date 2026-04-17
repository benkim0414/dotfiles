# Global Claude Code Preferences

## Preferences

- Editor: nvim
- Never use emojis in responses
- IMPORTANT: Never assume -- if requirements are ambiguous, underspecified, or
  open to multiple interpretations, ask clarifying questions before proceeding.
  This applies to task scope, implementation approach, edge cases, naming, and
  any decision that could go more than one way.

## Response style

- Explain the reasoning behind config choices, not just what to set
- Present the dry-run/plan/diff form of a command before the apply form; let the user review first
- Use the fetch MCP to look up current docs, API versions, or package versions -- training data goes stale; never guess at versions

## Verification & context

- Always verify work before reporting completion -- run the project's test
  suite, linter, type checker, or build command. If none exist, describe what
  manual verification the user should perform.
- When an approach fails, prefer rewind (double-tap Esc) over inline
  correction -- rewinding drops the failed attempt from context.
- Use `/compact <hint>` to focus compaction (e.g., "focus on auth refactor,
  drop test debugging"). Use `/clear` with a written brief for new tasks.

## Semantic Search (qmd)

When qmd is available as an MCP server and the current project has an indexed
collection, prefer qmd `query` over Glob/Grep for finding relevant code.
qmd returns semantically ranked results, which is more effective for:
- Finding implementations by describing what they do (not what they're named)
- Discovering related code across a large codebase
- Answering "where is X handled?" questions

Fall back to Glob/Grep when:
- qmd is not available or the project has no indexed collection
- You need exact string/regex matches (import paths, error messages, symbol names)
- You need to find all occurrences exhaustively (refactoring, renaming)

Never automate `qmd collection add`, `qmd embed`, or `qmd update` --
indexing is always a manual user action.

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
