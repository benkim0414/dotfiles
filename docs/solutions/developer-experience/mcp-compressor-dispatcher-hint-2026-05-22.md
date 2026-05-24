---
title: "[RETRACTED] MCP servers wrapped by mcp-compressor need an explicit dispatcher arg-shape hint"
status: retracted
superseded_by: "docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md"
date: 2026-05-22
category: developer-experience
module: claude
problem_type: developer_experience
component: tooling
severity: medium
applies_when:
  - "Using mcp-compressor-wrapped MCP servers in ~/.claude.json (atlassian, qmd, sequential-thinking, slack)"
  - "Running a fresh Claude Code session with no prior conversational context"
  - "Seeing `MCP error -32602: missing tool_name` from a dispatcher call"
  - "Debugging why a wrapped MCP tool ``works sometimes but not always''"
related_components:
  - tooling
  - documentation
  - assistant
tags:
  - mcp-compressor
  - mcp-dispatcher
  - claude-code
  - tool-schema
  - inputschema
  - dotfiles
---

> **RETRACTED 2026-05-22** — supersedes by `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`. The hint approach was abandoned when the compressor wrapper was dropped entirely.

---

# MCP servers wrapped by mcp-compressor need an explicit dispatcher arg-shape hint

## Context

Four MCP servers in `~/.claude.json` (atlassian, qmd, sequential-thinking, slack) are proxied through `uvx mcp-compressor` (Rust binary, latest version 0.23.0 on PyPI as of 2026-05-22). The wrapping is added by `bin/.local/bin/mcp-add` and uses the default `compressed-tools` transform mode. Each wrapped server therefore exposes only two dispatcher tools to MCP clients: `<server>_get_tool_schema` and `<server>_invoke_tool`.

Both dispatcher tools advertise `inputSchema: {"type": "object", "properties": {}}` over MCP, but server-side they actually require a `tool_name` (string) on both, plus `arguments` (object) on `_invoke_tool`. This empty schema is consistent across compressor versions 0.18.1, 0.20.0, 0.22.0, and 0.23.0 and across all four compression levels (`low`, `high`, `medium`, `max`). It is a design flaw in `compressed-tools` mode against schema-aware MCP clients like Claude Code, not a regression.

Fresh Claude Code sessions see a parameterless tool, call it with `{}`, and receive `MCP error -32602: missing tool_name`. Past sessions show fresh agents wasting 15-20+ dispatcher calls cycling through wrong arg shapes (`name`, `tool_name`+`arguments_json`, `tool_name`+flat keys, `tool_name`+`params`, `tool_name`+`input`, `tool_name`+`kwargs`, ...) before converging on what the compressor actually expects.

## Guidance

When calling a `mcp-compressor`-wrapped dispatcher from this dotfiles config, always supply both `tool_name` (the real backend tool name) and `arguments` (the backend's parameters as an inline object), even though the advertised inputSchema declares no parameters. The Claude Code harness does pass extra fields beyond the published schema to the MCP server — the empty schema is misleading, not enforcing.

Correct shape (Slack):

```text
mcp__slack__slack_get_tool_schema(tool_name="slack_list_channels")

mcp__slack__slack_invoke_tool(
  tool_name="slack_list_channels",
  arguments={"limit": 3},
)
```

Common wrong shapes to avoid:

```text
# Wrong: empty arguments -- triggers -32602
mcp__slack__slack_invoke_tool()

# Wrong: arguments serialized as a JSON string
mcp__slack__slack_invoke_tool(
  tool_name="slack_list_channels",
  arguments="{\"limit\": 3}",
)

# Wrong: flat keys at the dispatcher level
mcp__slack__slack_invoke_tool(
  tool_name="slack_list_channels",
  limit=3,
)

# Wrong: arguments under a different field name
mcp__slack__slack_invoke_tool(
  tool_name="slack_list_channels",
  params={"limit": 3},
)
```

The list of real backend tools lives in the dispatcher's own tool description — `Available tools are: <tool>...`. Read that description before the first call rather than probing arg shapes.

## Why This Matters

The empty `inputSchema` is an upstream defect in mcp-compressor's `compressed-tools` mode that will not heal itself locally — pinning to older versions does not help (the bug predates 0.18.1) and changing compression levels does not help (`low`/`medium`/`high`/`max` all produce the same empty schema). Until upstream ships a real schema, every fresh Claude session re-fumbles unless the project's own instruction file teaches the shape. The cost is real: 15-20 wasted dispatcher calls per cold start, the user perception that "the MCP is broken," and an LLM that may converge on an invalid shape that returns degraded output instead of erroring cleanly.

## When to Apply

- Calling any tool on `mcp__atlassian__*`, `mcp__qmd__*`, `mcp__sequential-thinking__*`, or `mcp__slack__*` from a Claude Code session that uses this dotfiles configuration.
- Triaging a `MCP error -32602: missing tool_name` response.
- A fresh session that has not yet succeeded in calling a wrapped MCP server.
- After upgrading `mcp-compressor`; verify the bug is still present (probe the dispatcher's `inputSchema` via `tools/list`). The hint stays applicable as long as the schema is empty.
- When debugging why a dispatcher tool appears to "work in one session and not another" — the difference is usually whether the earlier session converged through trial-and-error.

## Examples

Verified working in the 2026-05-22 session that produced this learning:

```text
mcp__slack__slack_get_tool_schema(tool_name="slack_list_channels")
# Returns the real schema for slack_list_channels:
# {"properties": {"limit": {...}, "cursor": {...}}, ...}

mcp__slack__slack_invoke_tool(
  tool_name="slack_list_channels",
  arguments={"limit": 3},
)
# Returns the actual channel list.
```

```text
mcp__atlassian__atlassian_get_tool_schema(tool_name="jira_get_issue")
# Returns the full schema for jira_get_issue, including the issue_key pattern.

mcp__atlassian__atlassian_invoke_tool(
  tool_name="jira_get_issue",
  arguments={"issue_key": "INFRA-362"},
)
# Returns the issue payload.
```

Error string future searches will hit on:

```
MCP error -32602: missing tool_name
```

## Related

- `claude/.claude/CLAUDE.md` -- the always-loaded global preferences file where the dispatcher hint lives (section `## MCP servers wrapped by mcp-compressor`).
- `docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md` -- brainstorm spec.
- `docs/superpowers/plans/2026-05-22-mcp-compressor-dispatcher-hint.md` -- implementation plan. Notes that the originally planned upstream issue against `atlassian-labs/mcp-compressor` is deferred.
- `bin/.local/bin/mcp-add` -- the wrapper script that produces the compressed-tools-mode entries.
