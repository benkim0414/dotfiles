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

All work happens on isolated worktree branches. Hooks enforce worktree
isolation, main-branch protection, and selective staging -- follow the
`[git-workflow]` context injection at session start.

`EnterWorktree` FIRST. All plan artifacts (brainstorm spec at
`docs/superpowers/specs/`, plan at `docs/superpowers/plans/`,
`ce-compound` solution doc at `docs/solutions/`) live inside the
worktree and merge with the feature.

### Canonical workflow

```
EnterWorktree
    ↓
brainstorming         (design + spec)
    ↓
writing-plans         (step-by-step plan)
    ↓
subagent-driven-development     (TDD + systematic-debugging inline)
    ↓
verification-before-completion
    ↓
requesting-code-review          (re-invoke after fixes until clean)
    ↓
ce-compound                     (capture learnings -> docs/solutions/)
    ↓
finishing-a-development-branch
   ├─ no-pr default: option 1 (local merge -> push main)
   └─ PR mode:       compound-engineering:ce-commit-push-pr +
                     compound-engineering:ce-resolve-pr-feedback
```

Full integration details: `~/.claude/docs/superpowers-workflow.md`

### Commit rules

- Commit each self-contained logical change atomically.
- Conventional commits: `type(scope): description` -- types: feat, fix,
  docs, chore, refactor, test, ci, perf.
- Stage specific files; never `git add -A` or `git add .` (hook-enforced).

### No-pr mode (default)

After implementation + `requesting-code-review` is clean +
`ce-compound` has documented the solution: invoke
`finishing-a-development-branch`, pick option 1 (local merge). Then
push main. No PR created.

### PR mode (opt-in)

When a PR is needed:

- `compound-engineering:ce-commit-push-pr` -- commit, push, and open
  the PR with an adaptive value-first description (replaces older
  `/pr:create`).
- `compound-engineering:ce-resolve-pr-feedback` -- address review
  threads (replaces older `/pr:address`).
- After merge: `ExitWorktree("keep")` to return to main.
- YOU MUST use merge commits (`gh pr merge --merge`), never squash or
  rebase.

### Worktree exit

- `ExitWorktree("keep")` after merge (default).
- `ExitWorktree("remove")` only for exploratory work with no commits.

## Plugin integration

`superpowers@superpowers-marketplace` and
`compound-engineering@compound-engineering-plugin` are both enabled.
Skill chain documented above.

Caveats:

- Worktree management uses the harness `EnterWorktree` / `ExitWorktree`
  tools (hook-enforced) -- NOT `superpowers:using-git-worktrees`.
- Parallel agents: use `caveman:cavecrew` for compressed delegation
  when context budget matters; use
  `superpowers:dispatching-parallel-agents` for the standard parallel
  pattern.
- Skill authoring: use the separate `skill-creator` plugin if needed.
