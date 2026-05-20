# Codex GitHub Approval Policy Design

## Purpose

Codex should keep the current `workspace-write` sandbox and worktree isolation
model, while reducing prompts for routine GitHub collaboration work. Agents
should be able to use GitHub PR, issue, and branch sync workflows from an
isolated worktree without asking the user every time, as long as the operation
does not merge, rewrite history, delete shared state, access credentials, or
escape the configured workspace boundary.

## Scope

Update the approval contract in:

- `codex/.codex/config.toml`
- `codex/.codex/config.base.toml`
- `codex/.codex/AGENTS.md`

The change is policy-only. It does not change `approval_policy`, sandbox mode,
the worktree guard hook, or the context-mode hooks.

## Auto-Approved GitHub Operations

The auto reviewer may approve GitHub-scoped operations when they are issued from
the active repository worktree and are limited to collaboration or normal branch
sync:

- `gh pr view`, `list`, `create`, `edit`, `comment`, `check`, `status`, and
  `review`
- `gh issue view`, `list`, `create`, `edit`, `comment`, and `status`
- `git fetch`, `git pull`, and ordinary `git push` for GitHub remotes

Persistent approval rules for these operations must remain narrow and
command-specific. Examples include `["gh", "pr"]`, `["gh", "issue"]`,
`["git", "fetch"]`, `["git", "pull"]`, and `["git", "push"]`.

## Denied Operations

The auto reviewer must continue to deny operations with higher risk or broader
network scope:

- `gh pr merge`
- branch deletion and repository administration
- settings, secrets, token, credential, and workflow permission changes
- destructive issue, PR, or repository operations
- force pushes, history rewrites, rebases that rewrite shared history, and
  broad branch mutation commands
- non-GitHub network access
- direct GitHub API access through arbitrary runtimes or shell scripts
- writes outside configured workspace roots
- destructive shell commands

These operations still require direct user approval.

## Worktree Boundary

The worktree guard remains the local safety boundary for repository writes. The
GitHub approval relaxation depends on that boundary: routine PR, issue, fetch,
pull, and ordinary push commands can proceed from a linked worktree, while local
writes in the main worktree remain blocked by the hook.

## Testing

Verification is static because the change is approval policy text:

- Confirm `config.toml` and `config.base.toml` have matching auto-review policy
  wording.
- Confirm `AGENTS.md` describes the same GitHub allowance and deny list.
- Run any available config parse or formatting check if the repository provides
  one.
