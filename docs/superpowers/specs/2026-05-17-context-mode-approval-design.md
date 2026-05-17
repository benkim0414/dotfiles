# Context Mode Approval Design

## Goal

Allow Codex to use all `context-mode` MCP tools without prompting for approval,
while preserving the existing approval posture for unrelated shell commands and
tools.

The change should cover direct MCP operations such as `ctx_search`,
`ctx_execute`, `ctx_batch_execute`, `ctx_fetch_and_index`, `ctx_index`, and
`ctx_doctor`. Shell commands that invoke the `context-mode` binary are a
separate approval surface and should not force a global approval-policy change.

## Current State

The dotfiles repository manages durable Codex settings in
`codex/.codex/config.base.toml`. The live `codex/.codex/config.toml` is
generated from that base file by `bin/.local/bin/codex-sync`.

`context-mode` is already registered as a Codex MCP server:

```toml
[mcp_servers.context-mode]
# Launch context-mode as a Codex MCP server.
command = "context-mode"
```

Codex currently keeps:

```toml
approval_policy = "on-request"
```

That setting should remain in place so non-context-mode approval-sensitive work
continues to prompt when needed.

## Requirements

- Auto-approve all tools exposed by the `context-mode` MCP server.
- Keep `approval_policy = "on-request"`.
- Do not broaden approval bypasses for unrelated shell commands.
- Preserve the existing context-mode MCP server registration.
- Regenerate `codex/.codex/config.toml` from `config.base.toml`.
- Verify the generated config contains the same approval setting.

## Design

Set the `context-mode` MCP server's default tool approval mode to `approve`:

```toml
[mcp_servers.context-mode]
# Launch context-mode as a Codex MCP server.
command = "context-mode"
# Allow all context-mode MCP tools without per-call approval prompts.
default_tools_approval_mode = "approve"
```

This uses Codex's MCP server tool-approval configuration instead of changing the
global approval policy. It applies to MCP tool calls for the `context-mode`
server and leaves normal shell approval behavior under `approval_policy =
"on-request"`.

## Shell Command Scope

Shell commands such as these are not MCP tool calls:

```bash
context-mode doctor
context-mode hook codex pretooluse
context-mode upgrade
```

Codex does not expose a verified durable `config.toml` allowlist for only those
shell-command prefixes in the current schema. If a future session asks to run a
shell command that requires approval, the approval UI can still offer a
session/prefix approval for `context-mode`. The durable dotfiles change should
not switch to `approval_policy = "never"` just to cover this shell surface,
because that would suppress approvals globally.

## Data Flow

1. Codex starts and reads `~/.codex/config.toml`.
2. The `context-mode` MCP server is registered from
   `[mcp_servers.context-mode]`.
3. Codex applies `default_tools_approval_mode = "approve"` to tools from that
   MCP server.
4. Calls to `mcp__context_mode__*` tools run without approval prompts.
5. Unrelated shell commands and approval-sensitive actions continue to follow
   `approval_policy = "on-request"`.

## Error Handling

- If Codex rejects `default_tools_approval_mode`, check the active Codex version
  and the current schema before changing approval policy.
- If a context-mode MCP operation still prompts after config regeneration,
  verify that `codex-sync` copied the base config into the live config and
  restart the Codex session.
- If shell commands still prompt, treat that as expected unless a prefix approval
  was granted in the current session.

## Testing

- Confirm the base config contains the MCP approval mode:

```bash
rg -n 'default_tools_approval_mode = "approve"' codex/.codex/config.base.toml
```

- Regenerate the live config:

```bash
bin/.local/bin/codex-sync
```

- Confirm the generated config preserves both settings:

```bash
rg -n 'approval_policy = "on-request"|default_tools_approval_mode = "approve"' \
  codex/.codex/config.toml
```

- Run context-mode diagnostics through the MCP tool surface:

```text
mcp__context_mode__ctx_doctor
```

## Out of Scope

- No change to `approval_policy`.
- No global `approval_policy = "never"` mode.
- No shell-command prefix allowlist unless Codex exposes a durable, documented
  config mechanism for it.
- No changes to context-mode hook registration.
