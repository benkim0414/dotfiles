---
title: "Inherit scoped Codex approvals in subagents"
date: "2026-05-19"
category: "workflow-issues"
module: "dotfiles/codex"
problem_type: "workflow_issue"
component: "assistant"
severity: "medium"
applies_when:
  - "Codex subagents repeatedly ask for approvals the main session can usually handle automatically"
  - "Approval behavior must persist through durable Codex config rather than session-local grants"
  - "Routine repository work should proceed without weakening approval boundaries"
symptoms:
  - "Subagents interrupt workflow with repeated approval prompts"
  - "Main-session approvals do not reliably carry into separate subagent sessions"
  - "Approval-sensitive Codex settings risk being dropped during config sync"
root_cause: "config_error"
resolution_type: "config_change"
related_components:
  - "development_workflow"
  - "tooling"
  - "testing_framework"
  - "documentation"
tags:
  - "codex-cli"
  - "subagents"
  - "approvals"
  - "auto-review"
  - "codex-sync"
  - "dotfiles"
---

# Inherit scoped Codex approvals in subagents

## Context

Subagents in this dotfiles repo were repeatedly asking for approval on routine
operations that the main Codex session could usually handle without
interruption. The key realization was that subagents behave like separate Codex
sessions: one-off runtime approvals from the main session should not be assumed
to carry into spawned workers.

The durable inheritance layer is `codex/.codex/config.base.toml`. That file is
copied to the generated `codex/.codex/config.toml` by `bin/.local/bin/codex-sync`
and wired into `$CODEX_HOME/config.toml`, so main sessions and subagents can
read the same durable policy.

Session history search found no relevant prior sessions for this specific
approval-inheritance problem.

## Guidance

Use scoped durable approval inheritance. Keep the global approval boundary in
place and route routine approval requests through Codex's risk-based reviewer:

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"
approvals_reviewer = "auto_review"
```

Then define a narrow `[auto_review]` policy in `codex/.codex/config.base.toml`:

```toml
[auto_review]
# Keep the reviewer narrow: routine repo work can proceed, boundary crossings
# still require explicit user intent or a durable scoped rule.
policy = """
Approve routine sandbox-compatible repository work: read-only commands, status
inspection, diffs, formatting checks, and test commands that write only inside
the active workspace or temporary directories.

Deny destructive commands, broad arbitrary shell approvals, network access,
credential access, writes outside configured workspace roots, and history
rewrites. These sensitive operations require direct user approval and must not
be approved by auto-review.

When an approval request includes a persistent prefix rule, approve only narrow
command-specific prefixes. Do not approve broad runtime prefixes such as bash,
python, node, ruby, perl, or sh.
"""
```

Keep trusted MCP approval scoped to the trusted server instead of changing
global approval behavior:

```toml
[mcp_servers.context-mode]
default_tools_approval_mode = "approve"
```

Protect the sync path with section-aware regression tests. The important detail
is that tests verify where settings appear, not just that strings exist
somewhere in the generated file:

```bash
assert_top_level_contains "$CONFIG" 'approval_policy = "on-request"'
assert_top_level_contains "$CONFIG" 'approvals_reviewer = "auto_review"'
assert_table_contains "$CONFIG" '[auto_review]' 'Approve routine sandbox-compatible repository work'
assert_table_contains "$CONFIG" '[mcp_servers.context-mode]' 'default_tools_approval_mode = "approve"'
```

Document the operational contract in `codex/.codex/AGENTS.md` so future agents
preserve the boundary:

```markdown
- Subagents inherit durable Codex config from `$CODEX_HOME/config.toml`.
- Keep `approval_policy = "on-request"`; do not bypass the sandbox globally.
- Routine sandbox-compatible repository work should flow through the configured auto reviewer.
- Sensitive operations require direct user approval and must not be approved by auto-review.
- Persistent prefix rules must be narrow and command-specific.
```

## Why This Matters

This reduces approval fatigue for subagents without weakening the sandbox
model. Routine repository work can proceed through `auto_review`, while
sensitive operations still require direct user approval.

The important design choice is durability. Runtime one-off approvals stay
session-local unless Codex persists them as scoped rules. Durable defaults that
all sessions should share belong in `config.base.toml`, then flow through
`codex-sync` into the generated and live Codex config.

Avoid these shortcuts:

- Do not set global approval to never ask.
- Do not auto-approve destructive commands, network access, credential access,
  history rewrites, or writes outside workspace roots.
- Do not persist broad runtime prefixes like `bash`, `python`, `node`, `ruby`,
  `perl`, or `sh`.
- Do not invent unsupported TOML keys for durable command-prefix inheritance.
- Do not rely on unscoped string tests that could pass even if settings move to
  the wrong table.

## When to Apply

- Subagents repeatedly ask for approval on routine sandbox-compatible repo work.
- The main session has smoother approval behavior than spawned subagent sessions.
- Approval behavior is managed through checked-in Codex dotfiles.
- You need approval inheritance across sessions without disabling `on-request`.
- You have a sync step that generates or links `$CODEX_HOME/config.toml`.
- You need tests to prevent future config sync changes from dropping approval
  settings.

## Examples

Before, only the global approval policy was durable:

```toml
approval_policy = "on-request"
```

Subagents still asked repeatedly because routine approval behavior was not
expressed as durable reviewed policy.

After, the global boundary remains, but routine work flows through the
configured reviewer:

```toml
approval_policy = "on-request"
approvals_reviewer = "auto_review"

[auto_review]
policy = """
Approve routine sandbox-compatible repository work...
Deny destructive commands...
"""
```

The regression test should verify TOML placement. A loose `grep` for
`approvals_reviewer` is not enough; it could pass if the key moved under the
wrong table. Use helpers that inspect the top-level pre-table region and bounded
table bodies.

## Related

- `docs/solutions/tooling-decisions/configure-context-mode-for-codex-cli-2026-05-17.md`
  covers the same `config.base.toml` -> `codex-sync` -> generated/live config
  source-of-truth pattern for Codex hook registration.
- `docs/solutions/workflow-issues/superpowers-workflow-reorg-2026-05-19.md`
  covers the surrounding Superpowers and compound-engineering workflow context.
