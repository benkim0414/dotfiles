# Codex Goals Feature Design

## Summary

Enable Codex's native goals feature in the checked-in Codex configuration and apply it to the live Codex config through the existing sync workflow.

## Context

The dotfiles repo treats `codex/.codex/config.base.toml` as the source of truth for Codex configuration. The `codex-sync` script copies that file to `codex/.codex/config.toml` and wires the live `$CODEX_HOME/config.toml` when run from the primary dotfiles checkout or when `CODEX_HOME`/`CODEX_SYNC_LIVE` requests live wiring.

OpenAI's Codex documentation says `/goal` is enabled by setting `goals = true` under `[features]` in `config.toml`. The current base config already has a `[features]` table, but it does not define `goals`.

## Goals

- Enable the Codex `/goal` feature by default for this dotfiles Codex setup.
- Keep the checked-in base config as the source of truth.
- Apply the change to the generated/live config with the existing `codex-sync` workflow.
- Preserve the existing approval, sandbox, hook, MCP, plugin, and AGENTS behavior.

## Non-goals

- Do not create or start a Codex goal as part of this change.
- Do not change Codex hooks, approval policy, sandbox policy, MCP server configuration, plugin configuration, or AGENTS instructions.
- Do not add a custom wrapper around Codex's native feature flag.

## Design

Add `goals = true` under the existing `[features]` section in `codex/.codex/config.base.toml`. Include a short comment in the same style as the surrounding config comments so the purpose is clear when reading the file.

After the config edit, run `codex-sync`. This keeps `codex/.codex/config.toml` aligned with the source config and updates the live Codex config according to the script's existing rules.

## Validation

Run the existing Codex sync test suite:

```sh
codex/.codex/tests/test-codex-sync-hooks.sh
```

Then run:

```sh
bin/.local/bin/codex-sync
```

Optionally inspect the generated config to confirm `[features]` contains `goals = true`.

## Risks

The goals feature can let Codex work for a long time toward a durable objective. This change only exposes the native feature; actual usage still requires an explicit `/goal` request and a clear stopping condition.
