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
- When implementation is complete: run `/review-cl` to self-review and create the PR.
  Push with an explicit refspec (`git push origin HEAD:<branch>`) to avoid
  `push.default=upstream` redirecting to main. Stay in the worktree after PR creation.
- When the PR is approved: `ExitWorktree("keep")` to return to main.
  Use `ExitWorktree("remove")` only to discard exploratory work with no commits.
- After ExitWorktree: wait for the user to merge. Do NOT run `gh pr merge` proactively.
- After merge: `/merge-pr` handles finalization (update main, remove worktree, delete branch).
- To resume an open PR: start Claude Code from within the worktree directory.

## Hook Architecture

Seven hooks enforce workflow guardrails (configured in `settings.base.json`):

- **SessionStart** (`git-session-start.sh`): inject git context, detect merged branches, set pending-worktree state
- **PreToolUse/Bash** (`bash-pretool.sh`): block commit/push/merge on main, enforce selective staging, inject commit scopes
- **PreToolUse/Write|Edit** (`worktree-guard.sh`): block file edits until EnterWorktree() is called
- **PreToolUse/AskUser|ExitPlan** (`notify.sh`): desktop notification when Claude needs attention
- **PostToolUse/EnterWorktree** (`worktree-entered.sh`): clear pending-worktree marker
- **PostToolUse/ExitWorktree** (`worktree-exited.sh`): remind next steps (merge PR or push)
- **PostToolUse/mutations** (`audit-log.sh`): JSONL audit trail in `~/.claude/logs/`

If a hook blocks unexpectedly: check the stderr message. Emergency escape for worktree
guard: `rm ~/.claude/session-worktrees/pending-<session-id>`.

## Git Discipline
- Conventional commits: `type(scope): description` -- types: feat, fix, docs, chore, refactor, test, ci, perf
- Write a commit body when the why is not obvious from the title
- Review diffs for accidental secrets before every commit
- Always use merge commits (`gh pr merge --merge`), never squash or rebase -- preserve full commit history

## Security
- Never hardcode secrets, tokens, or credentials in version-controlled files
- Rotate secrets immediately after accidental exposure; deleting commits is insufficient
- Least privilege: grant only the permissions actually needed
- Prefer dedicated secret management tools over environment variables or config files
- Audit new tool installations and third-party scripts before running them

## Domain Rules

DevOps rules (K8s, Docker, GHA, Terraform, Helm, shell) are in
`~/.claude/includes/devops.md`. Add `@includes/devops.md` to project-level
CLAUDE.md files in repos that need them.
