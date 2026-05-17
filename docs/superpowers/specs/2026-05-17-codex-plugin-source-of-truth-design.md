# Codex Plugin Source Of Truth Design

## Problem

New Codex sessions require manually running `codex-plugins-sync` before plugins are available. The local generated config, `codex/.codex/config.toml`, contains the enabled plugin sections, but the checked-in source config, `codex/.codex/config.base.toml`, only declares plugin marketplaces. When `config.toml` is regenerated from `config.base.toml`, the plugin enablement entries disappear.

## Goal

Make `codex/.codex/config.base.toml` the durable source of truth for enabled Codex plugins so regenerated sessions keep Superpowers and Compound Engineering enabled without manual repair.

## Non-Goals

- Do not track plugin cache contents under `codex/.codex/plugins/`.
- Do not add a startup hook that runs `codex-plugins-sync`.
- Do not change unrelated Codex hook state or runtime-generated config state.

## Design

Add the existing plugin enablement sections from `codex/.codex/config.toml` to `codex/.codex/config.base.toml`:

```toml
[plugins."superpowers@superpowers-marketplace"]
enabled = true

[plugins."compound-engineering@compound-engineering-plugin"]
enabled = true
```

Keep the sections near the marketplace declarations so the relationship is clear: marketplaces define where plugins come from, and plugin sections define which installed plugins should be enabled.

`codex-plugins-sync` remains a repair and installation helper. It should not be required during normal startup once the base config is regenerated into the active config.

## Data Flow

1. `codex-sync` copies `codex/.codex/config.base.toml` to `codex/.codex/config.toml`.
2. The active Codex config includes both marketplace declarations and plugin enablement entries.
3. Codex starts with the Superpowers and Compound Engineering plugin entries present.
4. `codex-plugins-sync` is only needed if the plugin cache is missing or stale.

## Error Handling

If a plugin cache is missing, Codex may still need `codex-plugins-sync` to install the plugin artifact. That is a separate repair path from preserving enabled plugin configuration. The fix makes config regeneration stable; it does not vendor or commit runtime plugin caches.

## Testing

Verification should confirm:

- `codex/.codex/config.base.toml` contains both `[plugins."..."]` sections.
- Running `codex-sync` preserves those sections in `codex/.codex/config.toml`.
- The final diff does not include plugin cache files or unrelated runtime state.
