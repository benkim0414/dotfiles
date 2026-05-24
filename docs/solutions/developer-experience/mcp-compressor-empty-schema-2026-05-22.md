---
title: "mcp-compressor compressed-tools mode is incompatible with Claude Code for required-arg tools"
date: 2026-05-22
category: developer-experience
module: claude
problem_type: integration_issue
component: tooling
severity: high
applies_when:
  - "Wrapping an MCP backend with uvx mcp-compressor in transform mode compressed-tools"
  - "Calling required-arg tools on the wrapped server through Claude Code"
  - "Backend reports pydantic 'Missing required argument [input_value={}]'"
symptoms:
  - "Every required-arg dispatcher call returns input_value={} regardless of argument shape"
  - "get_tool_schema calls succeed (no backend forwarding) but invoke_tool calls fail"
root_cause: empty_inputschema_strict_validator
resolution_type: drop_wrapper
related_components:
  - mcp-compressor
  - claude-code
  - mcp-atlassian
tags:
  - mcp
  - mcp-compressor
  - claude-code
  - schema-validation
  - debugging
  - stdio-bisect
---

# mcp-compressor compressed-tools mode is incompatible with Claude Code for required-arg tools

## Problem

Calling any required-arg tool on an MCP server wrapped by
`uvx mcp-compressor` (transform mode `compressed-tools`) through Claude
Code produced a pydantic validation error from the backend:

```
1 validation error for call[get_user_profile]
user_identifier
  Missing required argument [type=missing_argument, input_value={}, input_type=dict]
```

The backend received an empty argument dict regardless of how the
caller serialised `arguments`, on every available compressor release
from 0.10.0 through 0.23.0.

## Root cause

The compressor's `compressed-tools` mode exposes two dispatcher tools
per backend (`<server>_get_tool_schema`, `<server>_invoke_tool`) with
the following advertised schema:

```json
{ "type": "object", "properties": {} }
```

Claude Code's MCP client validates the `arguments` payload of a
`tools/call` request against the advertised `inputSchema` and strips
any key that is not declared in `properties`. Because the dispatcher
declares no properties, every key the caller supplies is stripped
before the request reaches the compressor. The compressor sees an
empty arguments dict and forwards an empty dict to the backend, which
fails required-arg validation.

A raw stdio bisect (spawning
`uvx --from mcp-compressor==X.Y.Z mcp-compressor --server-name atlassian
-- uvx mcp-atlassian` directly, sending `tools/call` JSON-RPC, and
observing the backend response) showed that the actual magic key for
`invoke_tool` is `tool_input`, not `arguments`. Raw stdio calls with
`tool_input` succeed against the backend on every compressor version
tested. Through Claude Code, both `arguments` and `tool_input` are
stripped because neither is declared in the empty schema.

The `get_tool_schema` path appears to work through Claude only because
the compressor handles `tool_name` locally without forwarding the
arguments dict to the backend; the bug is invisible until the caller
needs to actually invoke a backend tool with required parameters.

## Investigation method

Stdio bisect script (Python). Launch each compressor version directly,
send `initialize` plus a `tools/call` invoking
`jira_get_user_profile(user_identifier="x@example.com")`, observe the
backend's response payload. Argument-shape variants to exercise (the
full matrix described in
`docs/superpowers/specs/2026-05-22-atlassian-mcp-drop-compressor-design.md`):

1. Nested `arguments`: `{"tool_name": ..., "arguments": {"user_identifier": ...}}`
2. Flat at dispatcher level: `{"tool_name": ..., "user_identifier": ...}`
3. `tool_input` wrapper: `{"tool_name": ..., "tool_input": {"user_identifier": ...}}`
4. `input` wrapper: `{"tool_name": ..., "input": {"user_identifier": ...}}`
5. `kwargs` wrapper: `{"tool_name": ..., "kwargs": {"user_identifier": ...}}`
6. `params` wrapper: `{"tool_name": ..., "params": {"user_identifier": ...}}`
7. JSON-string `arguments`: `{"tool_name": ..., "arguments": "{\"user_identifier\":...}"}`

If the backend responds with a domain-specific error (e.g. "Could not
resolve email") the arguments reached it. If the backend responds with
`Missing required argument [input_value={}]`, the wrapper dropped them.

In `mcp-compressor` 0.22.0 only variant 3 (`tool_input`) reached the
backend; every other variant returned `input_value={}`. In 0.10.0
variants 2 (flat) and 3 (`tool_input`) both reached the backend, and
0.10.0's failure error format ("2 validation errors", echoing
`input_value={'arguments': {...}}`) revealed that the unrecognised
`arguments` wrapper was being passed through to the backend as a
literal key, rather than unwrapped. The compressor's expectations
shifted across versions; the empty `inputSchema` guarantees that no
caller can hit them through Claude Code.

## Resolution

Drop the `uvx mcp-compressor` wrapper for any server that exposes
required-arg tools through Claude Code. Add the backend directly with
`claude mcp add --scope user <name> -- <command>`. Accept the token-
list size increase relative to the dispatcher pair — broken tool calls
cost more than verbose tool catalogs.

The token-compression benefit can be recovered in the future via:

- `cli` or `just-bash` transform modes (different interface, not yet
  evaluated through Claude Code).
- A custom proxy that advertises real per-tool schemas while still
  compressing the underlying payload.
- claude.ai-hosted MCP servers (Atlassian, Slack, etc.) which expose
  full schemas natively.

## Generalisable lesson

When an MCP server advertises a dispatcher tool with
`"properties": {}`, treat it as **unusable through Claude Code for any
backend tool that has required arguments**. The empty schema is a
contract that the dispatcher accepts no input, and Claude's MCP client
enforces that contract.

Verify a wrapper's dispatcher schema *before* adopting it, by running:

```sh
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
} | <the wrapped command>
```

Both messages must travel down the same stdio stream — two separate
`echo | cmd` pipelines spawn fresh sessions and the second never sees
the first's `initialize` handshake. If the dispatcher tools return
`{"type":"object","properties":{}}`, the wrapper will not work through
Claude Code for required-arg calls.

## Related

- Retracted: `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md`
  (the 0.22.0-pin hypothesis).
- Retracted: `docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md`
  (the `arguments`-magic-key hint).
- Retracted: `docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md`
  (attributed the bug to a 0.23.0 regression).
- Current: `docs/superpowers/specs/2026-05-22-atlassian-mcp-drop-compressor-design.md`.
