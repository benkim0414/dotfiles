---
title: "Make Claude Code plugins reproducible across devices with extraKnownMarketplaces"
date: 2026-06-25
category: tooling-decisions
module: claude-code-config
problem_type: tooling_decision
component: tooling
severity: low
applies_when:
  - "Adding a Claude Code plugin that should appear on every device from synced dotfiles"
  - "A plugin is in enabledPlugins but fails to load on a fresh machine"
  - "Deciding how plugin marketplaces reach a newly set-up device"
tags: [claude-code, plugins, marketplaces, dotfiles, settings, cross-device]
---

# Make Claude Code plugins reproducible across devices with extraKnownMarketplaces

## Context

The dotfiles repo tracks Claude Code plugin state in
`claude/.claude/settings.base.json` via `enabledPlugins`, which `claude-sync`
merges into `~/.claude/settings.json`. Adding `insane-search` (from the
`fivetaku/gptaku_plugins` marketplace) surfaced a gap: `enabledPlugins` only
*toggles a plugin on*. It does not tell Claude Code where the plugin's
marketplace lives. Marketplace registration lived only in the runtime file
`~/.claude/plugins/known_marketplaces.json`, which is not stowed and not in the
repo, and no dotfiles script wrote it.

Consequence: every enabled plugin (`caveman`, `compound-engineering`,
`context-mode`, `superpowers`) was known only because its marketplace had been
added by hand on the current machine. A freshly set-up device would
enable-but-fail-to-register all of them. The gap had stayed latent because a
second device had never actually been bootstrapped.

## Guidance

Declare each plugin's marketplace in the `extraKnownMarketplaces` settings key
alongside `enabledPlugins`, both in the synced base settings. On a fresh device
Claude Code auto-installs every declared marketplace (after a one-time trust
prompt), so the full plugin set travels through synced settings alone — no
manual `/plugin marketplace add`, no bootstrap script.

```json
{
  "enabledPlugins": {
    "context-mode@context-mode": true,
    "insane-search@gptaku-plugins": true,
    "superpowers@superpowers-marketplace": true
  },
  "extraKnownMarketplaces": {
    "context-mode": {
      "source": { "source": "github", "repo": "mksglu/context-mode" },
      "autoUpdate": true
    },
    "gptaku-plugins": {
      "source": { "source": "github", "repo": "fivetaku/gptaku_plugins" },
      "autoUpdate": true
    },
    "superpowers-marketplace": {
      "source": { "source": "github", "repo": "obra/superpowers-marketplace" },
      "autoUpdate": true
    }
  }
}
```

Rules that make this correct:

- The `extraKnownMarketplaces` **key** must equal the marketplace-name suffix
  used in `enabledPlugins` (the part after `@`). A mismatch means the plugin id
  never resolves to a known marketplace.
- A plugin needs BOTH an `enabledPlugins` entry AND — unless it lives on the
  official Anthropic marketplace — an `extraKnownMarketplaces` entry.
- Omit the official marketplace (`claude-plugins-official`, used by
  `claude-md-management`): Claude Code auto-installs it on its own, so declaring
  it is unnecessary.
- `"autoUpdate": true` makes Claude Code refresh the marketplace and update its
  installed plugins at startup. The non-official default is `false`; `true`
  trades occasional surprise upgrades for staying current. Choose per repo.
- Both keys are objects, so `claude-sync`'s generic deep-merge handles them with
  no script change. Keep them in the base, not an overlay — they are personal
  cross-device config, not company-specific.

## Why This Matters

"Enabled" and "known" are two different facts in Claude Code, persisted in two
different places — `settings.json` (synced) and
`~/.claude/plugins/known_marketplaces.json` (runtime, per-machine). Syncing only
the first produces a config that works on the machine where marketplaces were
added by hand and silently fails everywhere else. `extraKnownMarketplaces`
collapses both facts into the one file dotfiles already sync, which is the whole
point of "share with devices."

## When to Apply

- Adding any non-official Claude Code plugin that should be reproducible from
  dotfiles.
- A plugin shows as enabled but does not load on a fresh or secondary device.
- Auditing why existing enabled plugins might not survive a clean install.

## Examples

Before — `enabledPlugins` only. On a fresh device the plugin is enabled but its
marketplace is unknown, so it never loads:

```json
"enabledPlugins": { "insane-search@gptaku-plugins": true }
```

After — marketplace declared too. Fresh device auto-installs `gptaku-plugins`
after a one-time trust prompt, then `insane-search` is active:

```json
"enabledPlugins": { "insane-search@gptaku-plugins": true },
"extraKnownMarketplaces": {
  "gptaku-plugins": {
    "source": { "source": "github", "repo": "fivetaku/gptaku_plugins" },
    "autoUpdate": true
  }
}
```

Verification that does not mutate live config (the worktree caveat: running
`claude-sync` re-stows `~/.claude`, so verify the edited base directly):

```bash
# every enabled plugin's marketplace (minus official) is declared
jq -e '
  (.enabledPlugins | keys | map(sub("^[^@]+@";""))
   | map(select(. != "claude-plugins-official")) | sort)
  == (.extraKnownMarketplaces | keys | sort)
' claude/.claude/settings.base.json
```

Post-merge, on the target device: `claude-sync` then `claude /doctor` to
confirm no settings schema errors; a fresh device shows the one-time trust
prompt per marketplace.

## Related

- [Layer company Claude config separately from personal](../architecture-patterns/company-vs-personal-claude-config-layering-2026-06-19.md) — the base/overlay merge model these keys ride on.
- Spec: `docs/superpowers/specs/2026-06-25-insane-search-plugin-design.md`
- Plan: `docs/superpowers/plans/2026-06-25-insane-search-plugin.md`
