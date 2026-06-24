# insane-search plugin + reproducible plugin marketplaces

Date: 2026-06-25
Status: approved

## Goal

Add the `insane-search` Claude Code plugin to the dotfiles-managed Claude
config, and make every plugin marketplace auto-register on a fresh device
through synced settings alone -- no manual `/plugin marketplace add`, no
bootstrap script.

`insane-search` (from the `gptaku-plugins` marketplace,
`fivetaku/gptaku_plugins`) is a resilient public-page reader for Claude Code:
it escalates fetch strategies when a normal fetch is blocked. No API keys. It
auto-installs its Python dependencies (`curl_cffi`, `yt-dlp`) via `uv` on first
use.

## Background

Plugin state in this repo is split across two layers:

- `enabledPlugins` (in `claude/.claude/settings.base.json`, synced by
  `claude-sync` into `~/.claude/settings.json`) -- toggles a plugin on/off.
- Marketplace registration -- which marketplace a plugin comes from. Until now
  this lived only in the runtime file `~/.claude/plugins/known_marketplaces.json`,
  which is not stowed and not in the repo. No dotfiles script registers it.

Consequence: `enabledPlugins` enables `caveman`, `compound-engineering`,
`context-mode`, `superpowers`, and `claude-md-management`, but their
marketplaces are only known because they were added by hand on this machine. A
fresh device would enable-but-fail-to-register every one of them. The repo has
never actually bootstrapped a second device, so this gap was latent.

## Mechanism

Claude Code settings expose `extraKnownMarketplaces`: a settings field that
declares a marketplace inline and **auto-installs** it on any device (after a
one-time trust prompt), then keeps it available. Paired with `enabledPlugins`,
the full plugin set becomes declarative and travels through the
`claude-sync`-generated `~/.claude/settings.json`.

This is the correct and only mechanism for the goal -- the design space is
about scope, not about how.

## Scope (decided)

- **Backfill all marketplaces**, not just `gptaku-plugins`. Same file, same
  pattern, low risk, and it directly fulfils "share with devices" by making the
  whole plugin set reproducible.
- **Claude Code only.** Codex (which vendors plugin caches under
  `codex/.codex/plugins/`) is out of scope; `insane-search`'s Codex
  compatibility is unverified and the request was Claude config across devices.

## Changes

### 1. `claude/.claude/settings.base.json`

Add a new top-level `extraKnownMarketplaces` block. Each entry sets
`autoUpdate: true` (decided) so Claude Code refreshes the marketplace and
updates its installed plugins at startup:

```json
"extraKnownMarketplaces": {
  "caveman": {
    "source": { "source": "github", "repo": "JuliusBrussee/caveman" },
    "autoUpdate": true
  },
  "compound-engineering-plugin": {
    "source": { "source": "github", "repo": "EveryInc/compound-engineering-plugin" },
    "autoUpdate": true
  },
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
```

`claude-md-management@claude-plugins-official` is intentionally absent:
`claude-plugins-official` is the official Anthropic marketplace, which Claude
Code auto-installs on its own. Declaring it in `extraKnownMarketplaces` is
unnecessary.

Add one line to the existing `enabledPlugins` block (keep alphabetical
ordering by plugin id):

```json
"insane-search@gptaku-plugins": true
```

### 2. `CLAUDE.md`

Fold the new convention into the existing "Claude Code settings (layered
merge)" section (not a new section). Document:

- Marketplaces are declared in `extraKnownMarketplaces` in
  `settings.base.json`; on a fresh device Claude Code auto-installs each one
  after a one-time trust prompt.
- Plugins are toggled in `enabledPlugins`; a plugin needs both an
  `enabledPlugins` entry and (unless it is on the official marketplace) an
  `extraKnownMarketplaces` entry for its marketplace.
- `claude-md-management` rides the auto-known official marketplace, so it has
  no `extraKnownMarketplaces` entry by design.
- `autoUpdate: true` on each entry means startup refresh + plugin updates.

## Decisions and rationale

- **`autoUpdate: true` on all entries** (per user). Trade-off accepted: startup
  refresh keeps plugins current at the cost of occasional surprise upgrades.
  This overrides the non-official default of `false`.
- **No `claude-sync` change.** `claude-sync` already deep-merges object keys
  (overlay wins); `extraKnownMarketplaces` is just another object key and needs
  no special handling. The block lives in the base, not an overlay -- it is
  personal cross-device config, not company-specific.
- **No Brewfile change.** `insane-search` auto-installs `curl_cffi` and
  `yt-dlp` via `uv` at first use, and `uv` is already in the Brewfile. Pinning
  those deps in the Brewfile is unnecessary (YAGNI).

## Verification

- Run `claude-sync`; assert the generated `~/.claude/settings.json` is valid
  JSON and contains both the `extraKnownMarketplaces` block (5 entries) and the
  new `enabledPlugins` line.
- Run `claude /doctor` (or check `/status`) to confirm no settings schema
  errors.
- Fresh-device auto-install cannot be fully exercised on this machine, where
  the existing marketplaces are already known and trusted. Manual verification:
  on the next clean device, a one-time trust prompt appears per marketplace,
  after which `insane-search` and the other plugins are active. This limitation
  is documented, not worked around.

## Risk

Low. The change is additive JSON in one settings file plus a docs edit.
Existing marketplaces are already known on this device, so no re-prompt is
expected locally.
