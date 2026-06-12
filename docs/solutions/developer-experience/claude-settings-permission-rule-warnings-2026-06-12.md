---
title: "Claude Code launch warnings from removed MultiEdit tool and bare mcp__* allow rule"
module: claude-settings
date: 2026-06-12
problem_type: developer_experience
component: tooling
severity: low
applies_when: "Editing permission rules in claude/.claude/settings.base.json (or any Claude Code settings.json)"
symptoms:
  - '"Permission deny rule \"MultiEdit(...)\" matches no known tool — check for typos."'
  - '"Invalid permission rule \"mcp__*\" was skipped: Wildcard tool name \"mcp__*\" is not supported in allow rules."'
tags:
  - claude-code
  - permissions
  - settings-json
  - multiedit
  - mcp
related_components:
  - claude-sync
---

# Claude Code launch warnings: removed MultiEdit tool and bare `mcp__*` allow rule

## Context

On `claude` launch the harness validates `~/.claude/settings.json` and prints
warnings for permission rules it cannot honor. Two rule shapes that were once
valid now warn:

```
Permission deny rule "MultiEdit(**/.env)" matches no known tool — check for typos.
... (one per MultiEdit rule)

Settings Warning  permissions.allow:
  Invalid permission rule "mcp__*" was skipped: Wildcard tool name "mcp__*"
  is not supported in allow rules.
```

The skipped rules are silently dropped — the rest of the file stays in effect.

## Guidance

Two independent constraints in the current Claude Code permission schema:

1. **`MultiEdit` is gone.** The batch-edit tool was folded into `Edit`. Any
   `MultiEdit`, `MultiEdit(...)`, or `MultiEdit` token inside a hook `matcher`
   references a non-existent tool. Remove every `MultiEdit` reference; the
   matching `Edit(...)` rule already covers the same path.

2. **Bare wildcards are invalid in `allow`.** An `allow` pattern must name the
   scope it widens. For MCP that means `mcp__<server>__*` (literal
   `mcp__<server>__` prefix, glob only after it) — never bare `mcp__*`. `deny`
   and `ask` rules *do* accept bare wildcards anywhere, so `mcp__*__*create*`
   and friends remain valid in those lists.

Two ways to satisfy constraint 2 for MCP:

- **Enumerate servers:** `mcp__atlassian__*`, `mcp__qmd__*`, etc. Pre-approves
  those servers; must add a line per new server.
- **Drop the allow entirely:** under `defaultMode: "auto"` the classifier
  judges each unmatched MCP call. Zero maintenance; `ask` mutation rules still
  gate writes. (This repo chose this option.)

In this repo, edit `claude/.claude/settings.base.json` — never the generated
`~/.claude/settings.json` — then run `claude-sync` to regenerate. Also scan
`CLAUDE.md` for prose that documents the old matcher strings or the `mcp__*`
allow; stale doc references are the same defect class.

## Why This Matters

The warnings are non-fatal but the affected rules are *silently dropped*. A
`MultiEdit(~/.ssh/*)` deny that warns is contributing no protection — if its
paired `Edit(...)` rule were ever missing, the secret path would be unguarded
with no error. Treat "matches no known tool" as a dropped rule, not cosmetic
noise.

## When to Apply

- Whenever launch prints "matches no known tool" or "was skipped" warnings.
- Before adding new MCP permission rules — put the server-scoped glob in
  `allow`, or rely on auto mode; put mutation wildcards in `ask`/`deny`.
- After a Claude Code upgrade that may have removed or renamed a tool.

## Examples

Allow list — before/after:

```jsonc
// before — invalid, skipped at launch
"allow": ["Edit", "MultiEdit", "Bash", "CronList", "mcp__*"]

// after — MultiEdit removed (Edit covers it); MCP dropped to auto-mode classifier
"allow": ["Edit", "Bash", "CronList"]
```

Deny list — `MultiEdit` removed, paired `Edit` retained:

```jsonc
// before
"Edit(~/.ssh/*)",
"MultiEdit(~/.ssh/*)",
// after
"Edit(~/.ssh/*)",
```

Hook matcher — drop only the `MultiEdit` token:

```jsonc
// before
"matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit|WebFetch"
// after
"matcher": "Bash|Write|Edit|NotebookEdit|WebFetch"
```

## Related

- `docs/solutions/conventions/claude-permissions-hardening.md` — the permission
  posture this repo hardens toward (secret-path deny rules, auto mode).
