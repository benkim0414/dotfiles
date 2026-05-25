---
title: Narrow `mcp__*` allow with explicit per-tool ask for destructive MCP tools
date: 2026-05-25
category: conventions
module: claude
problem_type: convention
component: tooling
severity: low
applies_when:
  - settings.base.json carries a broad `mcp__*` allow rule
  - the MCP server exposes a tool that is irreversible or modifies the host system
  - the destructive tool name does not match any existing `mcp__*__*<verb>*` ask wildcard
tags: [claude-permissions, mcp, context-mode, narrowing-allow, destructive-tools]
---

# Narrow `mcp__*` allow with explicit per-tool ask for destructive MCP tools

## Context

`claude/.claude/settings.base.json` keeps a single broad `mcp__*` entry in
`permissions.allow` so every MCP server (qmd, sequential-thinking, atlassian,
slack, claude.ai integrations, context-mode, future servers) skips the prompt
path. The trade-off: a server can ship a destructive tool whose name does not
match any existing `mcp__*__*<verb>*` ask wildcard, and that tool inherits the
silent allow.

Concrete case: the `context-mode` plugin exposes `ctx_purge` (wipes the FTS5
knowledge base, irreversible) and `ctx_upgrade` (pulls, builds, and installs
from GitHub). Neither name contains `delete`, `update`, `remove`, etc., so
neither is caught by the existing destructive-MCP ask wildcards. Both fall
through to the broad allow.

## Guidance

When a new MCP tool is destructive or modifies host state and is not caught by
any existing ask wildcard, append an explicit exact-name ask rule to
`permissions.ask`:

```json
"mcp__plugin_context-mode_context-mode__ctx_purge",
"mcp__plugin_context-mode_context-mode__ctx_upgrade"
```

Claude Code precedence: `deny > ask > allow`. An explicit `ask` entry overrides
the broad `mcp__*` allow for the named tool only. Read-only siblings keep the
silent allow.

After editing `settings.base.json`, run `claude-sync` to regenerate
`~/.claude/settings.json`. Worktree edits do not flow until merged to main and
re-synced -- see `claude-permissions-hardening.md` under "Pitfalls".

Document the override in `CLAUDE.md` under "Permission posture" so future
readers do not have to grep the JSON to learn why two tools re-enter the
prompt path despite the bulk allow.

## Why This Matters

The bulk `mcp__*` allow is intentionally optimistic -- it assumes server
authors expose read-mostly tool surfaces. That assumption breaks for any
plugin that ships maintenance tooling (purge, upgrade, factory-reset) under
the same prefix as its data-access tools. Without an explicit per-tool
override, a destructive call fires without the user seeing it.

The pattern is preferable to:

- **Narrowing the allow to read-only tools by name** -- the allow array would
  balloon to dozens of entries per server and break every time a server adds a
  new read tool.
- **Replacing the bulk allow with `mcp__<server>__*` per server** -- same
  problem at the server granularity; new servers default to prompting until
  someone notices.
- **Relying on the `mcp__*__*<verb>*` ask wildcards alone** -- only catches
  names that contain `create`, `delete`, `update`, etc. `ctx_purge` and
  `ctx_upgrade` are real-world counter-examples.

The narrow override keeps the optimistic-by-default posture for the 90% of
tools that need it while restoring safety on the few that don't.

## When to Apply

- Adding a new MCP plugin and the tools/list surface contains at least one
  irreversible or system-modifying tool whose name does not match an existing
  ask wildcard.
- Upgrading an MCP plugin and the changelog mentions a new destructive tool.
- Reviewing `permissions.allow` and finding a destructive tool that has been
  passing silently.

## Examples

Diff that lands the override (lines 200-202 of `settings.base.json`):

```diff
       "mcp__*__*patch*",
-      "mcp__*__*write*"
+      "mcp__*__*write*",
+      "mcp__plugin_context-mode_context-mode__ctx_purge",
+      "mcp__plugin_context-mode_context-mode__ctx_upgrade"
     ]
```

CLAUDE.md "Permission posture" companion note:

```markdown
- Two destructive context-mode tools are walked back into `ask` so
  they prompt despite the broad `mcp__*` allow:
  `mcp__plugin_context-mode_context-mode__ctx_purge` (wipes the FTS5
  knowledge base, irreversible) and
  `mcp__plugin_context-mode_context-mode__ctx_upgrade` (pulls, builds,
  and installs from GitHub). `ask` overrides `allow` per Claude Code
  precedence.
```

## Related

- `docs/solutions/claude-permissions-hardening.md` -- broader hardening of
  `defaultMode: "auto"` with the semantic policy hook; documents the
  precedence assumption (`deny > ask > allow`) that this pattern depends on.
- `docs/solutions/conventions/mcp-compressor-empty-schema-2026-05-22.md` --
  separate MCP failure mode (compressor dropped 2026-05-22); reinforces that
  blanket MCP wrappers are fragile.
- `claude/.claude/hooks/permission-policy.sh` -- complementary semantic layer
  that catches risky shapes the regex rules cannot express.
