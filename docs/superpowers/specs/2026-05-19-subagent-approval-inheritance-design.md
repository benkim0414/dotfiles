# Subagent Approval Inheritance Design

## Goal

Subagents should behave like the main Codex session for routine repository work without weakening the existing approval boundary. The fix should reduce repeated approval prompts in subagents by inheriting durable Codex configuration, while still requiring approval for sensitive operations.

## Current Context

The dotfiles repository manages Codex configuration from `codex/.codex/config.base.toml`. The `codex-sync` helper copies that file to `codex/.codex/config.toml` and wires the generated file into `$CODEX_HOME/config.toml` when live sync is allowed.

The current durable config uses:

- `sandbox_mode = "workspace-write"`
- `approval_policy = "on-request"`
- `default_tools_approval_mode = "approve"` for the `context-mode` MCP server
- trusted project entries in generated config

Subagents appear to run as separate Codex sessions. That means session-local one-off approvals from the main agent should not be assumed to exist in subagents. Durable config is the right inheritance layer.

## Recommended Approach

Use scoped durable inheritance:

1. Keep `approval_policy = "on-request"` as the global policy.
2. Ensure subagents receive the same durable Codex config as the main session.
3. Preserve existing MCP server auto-approval for trusted tools such as `context-mode`.
4. Add only narrow, durable command approvals if Codex exposes a config-backed mechanism for them.
5. Avoid broad approvals for arbitrary shells, scripting runtimes, destructive commands, network access, or writes outside the workspace.

This balances usability and safety. Subagents should not repeatedly prompt for normal sandboxed work or trusted MCP tools, but they should still ask before crossing important boundaries.

## Scope

In scope:

- Inspect Codex's supported config shape for durable approval inheritance.
- Update `codex/.codex/config.base.toml` only if there is a valid config-backed setting to express the desired behavior.
- Regenerate or verify `codex/.codex/config.toml` via `codex-sync`.
- Extend `codex/.codex/tests/test-codex-sync-hooks.sh` to assert approval-relevant settings survive sync.
- Add operator documentation if the best available fix is partly behavioral.

Out of scope:

- Setting global approval to never ask.
- Auto-approving destructive commands.
- Auto-approving arbitrary `bash`, `python`, `node`, or similar broad execution.
- Rewriting the subagent system or plugin internals unless local configuration cannot solve the issue.

## Components

### Codex Base Config

`codex/.codex/config.base.toml` remains the source of truth for durable approval behavior. Any new supported approval setting must be added here first.

### Generated Config

`codex/.codex/config.toml` is generated from the base config by `bin/.local/bin/codex-sync`. Implementation should verify the generated config contains the same approval-relevant settings.

### Sync Test

`codex/.codex/tests/test-codex-sync-hooks.sh` should assert that approval-relevant config is present after sync. This catches regressions where future sync changes drop the settings needed by subagents.

### Documentation

If Codex does not expose config-backed durable prefix inheritance for subagents, document the limitation and the operational contract:

- Subagents inherit checked-in config.
- Subagents should not request escalation for sandboxed reads or workspace writes.
- Subagents should request escalation only for boundary-crossing work and use narrow `prefix_rule` values when persistence is appropriate.

## Data Flow

1. The operator edits `config.base.toml`.
2. `codex-sync` copies it to `config.toml`.
3. `codex-sync` links `$CODEX_HOME/config.toml` to the generated config.
4. Main Codex sessions and spawned subagent sessions read the same durable config.
5. Runtime one-off approvals remain session-local unless Codex stores them as scoped durable rules.

## Error Handling

If `codex-sync` cannot safely wire live config, it should keep its current behavior: generate the local config and print the existing message about `CODEX_HOME` or `CODEX_SYNC_LIVE=1`.

If a live config path is unmanaged, sync should refuse to replace it rather than silently overwriting user state.

If no supported config field exists for durable command-prefix approval inheritance, implementation should not invent an unsupported TOML shape. It should document the limitation and test the settings that are supported.

## Testing

Run:

```bash
codex/.codex/tests/test-codex-sync-hooks.sh
```

Also verify with targeted searches that both base and generated configs contain the expected approval settings.

## Success Criteria

- Subagents use the same durable Codex config as the main session.
- Trusted MCP tool approval remains configured in the base and generated config.
- The global approval policy remains `on-request`.
- Tests protect approval-relevant sync behavior.
- Sensitive actions still require explicit approval.
