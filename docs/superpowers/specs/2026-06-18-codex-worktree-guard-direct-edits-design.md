# Codex Worktree Guard Direct-Edit Design

## Goal

Reduce false-positive interruptions from the Codex worktree guard while preserving
the core protection against accidentally editing the primary checkout.

The current Codex guard is attached to shell, MCP, and direct edit tools. That
makes ordinary exploration and verification commands approval-heavy in the
primary checkout. Claude Code's guard is narrower: it protects direct file-edit
tools and leaves shell usage to the normal permission model. Codex should follow
that shape while keeping Codex-specific path checks for direct edit tools.

## Non-Goals

- Do not redesign the full Codex permission policy.
- Do not remove sandbox or approval-reviewer protections.
- Do not add a new session-state system like Claude Code's pending-worktree
  marker.
- Do not relax protections for direct edits to files in the primary checkout in
  this first pass.

## Behavior

Worktree isolation enforcement moves to direct edit surfaces only:

- `apply_patch`
- `Edit`
- `Write`
- `MultiEdit`
- `NotebookEdit`

Shell and MCP execution tools are no longer matched by `worktree-guard.sh`.
Commands such as `rg`, `find`, `git status`, `git log`, `git diff`, and focused
test scripts can run in the primary checkout without this guard requiring
approval. Shell-created files, such as `touch generated.txt`, are also outside
this guard's scope and rely on Codex sandboxing and approval policy instead.

Direct edit behavior remains path-aware:

- Direct edits that target the primary worktree require explicit approval.
- Direct edits that target a registered linked worktree are allowed.
- Direct edits outside a git repository are allowed.
- Cross-boundary direct edits from a linked worktree back into the primary
  worktree require explicit approval.
- New files created through direct edit tools in the primary worktree remain
  guarded for now, because they still create repo artifacts in the checkout that
  the worktree workflow is meant to keep clean.

## Configuration

`codex/.codex/config.base.toml` should narrow the worktree-guard
`PreToolUse.matcher` from shell/MCP coverage to direct edit tools only.

The context-mode hook can keep its broad matcher. It indexes context and should
not enforce worktree isolation.

The atomic commit hook remains Bash-only and unchanged.

## Script Shape

`codex/.codex/hooks/worktree-guard.sh` can retain its existing path
classification helpers for direct tool targets. The implementation should remove
or bypass shell and MCP executor enforcement paths once the config no longer
routes those tools to the guard.

The script should still gracefully exit for unrecognized tools so stale user
configs do not become disruptive.

## Testing

Update `codex/.codex/tests/test-codex-sync-hooks.sh` to assert the generated
Codex config uses the narrower worktree-guard matcher.

Replace the current MCP executor denial expectation with direct edit fixtures:

- direct edit target in a primary worktree returns a deny decision
- direct edit target in a registered linked worktree exits successfully
- direct edit target outside a git repository exits successfully

The test should keep existing sync assertions for hook wiring, agentmemory,
context-mode, and atomic commits.

## Success Criteria

- Running read-only or verification shell commands from the primary checkout is
  not blocked by the worktree guard.
- Direct file-edit tools still require approval before modifying files in the
  primary checkout.
- Linked worktree direct edits remain allowed.
- The sync test documents the narrower matcher and the direct-edit protection
  behavior.
