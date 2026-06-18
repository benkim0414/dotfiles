# Agentmemory Codex Plugin Install Design

## Goal

Install agentmemory for the Codex configuration through the supported Codex
plugin path, while preserving the existing context-mode setup and avoiding
manual references to versioned plugin cache paths.

## Context

The dotfiles repository stores Codex configuration under `codex/.codex/`.
`codex/.codex/config.toml` is the active generated/user config snapshot, and
`codex/.codex/config.base.toml` is the durable source used for the checked-in
base configuration.

The current Codex config already includes:

- `context-mode` as an MCP server with `default_tools_approval_mode = "approve"`.
- lifecycle hooks for `SessionStart`, `UserPromptSubmit`, `PreToolUse`,
  `PostToolUse`, `PreCompact`, and `Stop` that call `context-mode hook codex`.
- plugin marketplace entries for Superpowers and Compound Engineering.

The current main checkout also has an unrelated modification to
`codex/.codex/hooks/worktree-guard.sh`. The agentmemory work must not touch or
revert that file unless a later implementation step discovers a direct need.

## Recommended Approach

Use the official Codex plugin installation flow:

```sh
codex plugin marketplace add rohitg00/agentmemory
codex plugin add agentmemory@agentmemory
```

This lets Codex resolve the plugin manifest, MCP server registration, skills,
and hook wiring using its own plugin platform. It avoids brittle hand-written
hook paths that embed cache versions.

After installation, inspect the generated config diff and commit only the
stable configuration needed for reproducibility in this dotfiles repository.
The expected durable config is a marketplace entry for `agentmemory` and an
enabled plugin entry for `agentmemory@agentmemory`; generated timestamps,
revision pins, or local cache state should only be committed if that matches
the repo's existing Codex plugin pattern after inspection.

## Alternatives Considered

### Manual plugin config

Directly edit `codex/.codex/config.base.toml` to add the marketplace and plugin
entries. This keeps the change small, but it risks missing generated metadata
or plugin-platform behavior that `codex plugin add` handles.

### MCP-only config

Add only an `[mcp_servers.agentmemory]` block pointing at `npx -y
@agentmemory/mcp`. This gives Codex memory tools but does not install the
Codex plugin skills or lifecycle hooks, so it does not satisfy the requested
full plugin install.

### Plugin plus explicit hook fallback

Install the plugin and also run `agentmemory connect codex --with-hooks` to
mirror hook commands into a global hooks file. This may be useful if plugin
hooks do not fire in a specific Codex surface, but it should not be the initial
path because it can duplicate lifecycle capture and introduce absolute paths
that need refresh after upgrades.

## Architecture

`context-mode` and `agentmemory` should remain separate integrations:

- `context-mode` continues to provide local searchable session/tool context
  through its existing MCP server and lifecycle hooks.
- `agentmemory` is added as a Codex plugin that registers its own MCP server,
  lifecycle hooks, and user-facing skills.

No existing context-mode hook or MCP configuration should be removed as part of
this installation. If both systems capture the same lifecycle events, that is
an accepted consequence of running both memory systems unless verification
shows a concrete conflict.

## Components

- `codex/.codex/config.toml`: inspect after plugin installation because Codex
  may update generated marketplace metadata here.
- `codex/.codex/config.base.toml`: update with durable, hand-maintained plugin
  source-of-truth entries if the install proves they are needed for dotfiles
  reproducibility.
- Agentmemory server process: run separately with `npx @agentmemory/agentmemory`
  or an installed `agentmemory` command. Full MCP proxy behavior requires this
  server to be reachable, normally at `http://localhost:3111`.
- Codex plugin cache: managed by Codex. Do not hard-code paths into this cache.

## Data Flow

1. Codex loads marketplace and plugin entries from the user config.
2. The agentmemory plugin registers its MCP server and lifecycle hooks.
3. The plugin MCP shim talks to `AGENTMEMORY_URL` when set, otherwise it uses
   `http://localhost:3111`.
4. The running agentmemory server stores and retrieves memory across Codex
   sessions.
5. If the full server is unavailable, the MCP shim may expose a reduced local
   tool set, but full persistent memory requires the server.

## Error Handling

- If plugin installation needs network access, request approval for the exact
  install command instead of broad runtime permissions.
- If `codex plugin marketplace add` or `codex plugin add` fails, capture the
  failure and do not hand-edit cache paths as a workaround.
- If the agentmemory server is not running, report that full memory is blocked
  by runtime availability rather than treating the config install as failed.
- If plugin hooks do not appear to fire after verification, consider the
  explicit hook fallback as a separate follow-up with its own diff.

## Verification

The implementation should verify the install without relying on hidden state:

- Inspect `git diff` for both `codex/.codex/config.toml` and
  `codex/.codex/config.base.toml`.
- Run available `codex plugin` listing or status commands to confirm
  `agentmemory@agentmemory` is installed and enabled.
- Check whether `agentmemory` or `npx @agentmemory/agentmemory` can expose a
  health/status command without printing secrets.
- Confirm no changes were made to `codex/.codex/hooks/worktree-guard.sh`.

## Non-Goals

- Do not replace context-mode with agentmemory.
- Do not add manual MCP-only wiring unless the plugin path fails and the user
  explicitly approves the fallback.
- Do not add absolute hook script paths into checked-in config.
- Do not configure remote agentmemory credentials or secrets in the repository.
- Do not change Codex approval policy, auto-review policy, or unrelated hooks.
