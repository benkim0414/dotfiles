---
name: factory
description: Coordinate work through benkim0414/factory's existing CLI and manual worker workflow when explicitly requested.
disable-model-invocation: true
---

# Factory coordinator

Use this workflow only when the user explicitly invokes it. Factory means
benkim0414/factory, not Factory.ai or Droid.

Resolve the local Factory checkout from the current directory or a path supplied
by the user. If neither identifies it, ask for its location. Read its README,
package.json, and repository instructions before running commands. Use its
documented runtime and working directory; do not invent an HTTP or MCP API.

Start by inspecting Factory status. Existing tickets, attempts, worktree paths,
and review packets are authoritative. Reconcile them before proposing another
attempt. Commands below are subcommands of the repository's documented Factory
CLI entry point; consult its current help for exact arguments:

- `status`: inspect current work.
- `ticket create`: record a requested task and acceptance criteria.
- `workflow start` with runtime `manual`: prepare an attempt/worktree and render
  its worker prompt.
- `pane register` and `attempt attach-pane`: record a manually selected worker.
- `attempt prompt`: obtain the current worker prompt.
- `attempt manual-result-template` and `attempt ingest-manual`: collect and
  validate real worker evidence.
- `workflow review`: obtain the current approval packet.

These manual commands do not launch or control Herdr terminals. Tell the user
when a step requires opening a worker pane or delivering a prompt manually.
Do not claim automatic dispatch, background supervision, or worker cancellation
unless the current checkout supplies and verifies that capability.

The user primarily talks to this coordinator but can directly instruct workers
in their own Herdr terminals. Workers continue autonomously after those messages.
Record material scope changes in Factory before reviewing results. Do not infer
that you observed direct messages or that the worker reported them automatically.

Present the current task, blocker, next action, and evidence concisely. A pane's
idle state is not evidence of task completion. Never invent checks, exit codes,
digests, or a worker result. Approval applies to the current evidence snapshot
and requires the user's explicit authority. Follow repository permissions for
merging, publishing, credentials, and destructive operations.

Keep implementation changes in the prepared worker worktree. Do not configure
another orchestrator or add a Pi subagent package as part of this workflow.
