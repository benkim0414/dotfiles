---
title: Configure herdr keybindings to match tmux muscle memory
date: 2026-07-09
category: tooling-decisions
module: herdr
problem_type: tooling_decision
component: tooling
severity: low
applies_when:
  - Adopting herdr as the primary terminal/agent multiplexer while keeping tmux muscle memory
  - Wanting seamless direct ctrl+hjkl navigation across nvim splits and herdr panes
  - Deciding how to store a herdr config.toml in a Stow-managed dotfiles repo
tags: [herdr, tmux, keybindings, stow, neovim, terminal-multiplexer]
---

# Configure herdr keybindings to match tmux muscle memory

## Context

herdr (homebrew-core `brew "herdr"`) is an agent multiplexer — a tmux-style
terminal workspace manager (workspaces / tabs / panes) purpose-built for running
AI coding agents. Adopting it as the day-to-day driver meant its default keymap
(prefix `ctrl+b`, its own split/settings/nav bindings) collided with years of
tmux muscle memory. The goal was to make herdr feel like the existing tmux setup
without relearning keys, and to package the result reproducibly in the dotfiles
repo.

Three sub-problems had non-obvious answers: how to remap keys without fighting
herdr's defaults, how to get tmux's seamless `ctrl+hjkl` vim/pane navigation
(vim-tmux-navigator) in herdr, and how to store the config given herdr owns
`~/.config/herdr/`.

## Guidance

**1. Override only the keys that diverge — herdr merges `config.toml` with its
built-in defaults.** Never paste the full default keymap. A minimal `[keys]`
block is the idiomatic form (per herdr's own docs). Confirm defaults with
`herdr --default-config` (note: the printed key lines are *commented*, so grep
with `^#? *`).

```toml
# ~/.config/herdr/config.toml  (stowed from the herdr/ package)
onboarding = false

[keys]
prefix = "ctrl+s"               # tmux prefix; herdr default is ctrl+b
split_horizontal = "prefix+s"   # stacked (pane below): tmux muscle memory
settings = "prefix+comma"       # evicted from prefix+s so split can claim it
```

`split_vertical` stays at its `prefix+v` default (side-by-side), which already
matched. `resize_mode`/`reload_config`/`toggle_sidebar` (`prefix r`/`R`/`b`) were
deliberately left at herdr defaults. When one action must move off a key another
action wants (here `settings` off `prefix+s`), relocate the displaced action
first — herdr rejects nothing, so a silent double-bind is the risk.

**2. Direct `ctrl+hjkl` seamless nav comes from the `vim-herdr-navigation`
plugin — a vim-tmux-navigator port to herdr's CLI.** Bind the keys as
`plugin_action` custom commands; the plugin checks the focused pane's foreground
process (`herdr pane process-info`) and either forwards the key into vim
(`herdr pane send-keys`) or moves herdr focus (`herdr pane focus --direction`).
It falls back to tmux (`$TMUX`) or plain `wincmd` outside herdr, so an existing
tmux setup keeps working.

```toml
[[keys.command]]
key = "ctrl+h"
type = "plugin_action"
command = "vim-herdr-navigation.left"   # also .down / .up / .right
description = "navigate left (vim/herdr)"
```

Install the herdr-side plugin into herdr's own store (not Stow-managed, like
`tpm` for tmux):

```sh
herdr plugin install paulbkim-dev/vim-herdr-navigation --yes
herdr plugin action list --plugin vim-herdr-navigation   # verify left/down/up/right
```

On the nvim side, fold it into the existing `vim-tmux-navigator` lazy.nvim spec:
disable that plugin's own mappings and let the port own `<C-h/j/k/l>`.

```lua
{
  "christoomey/vim-tmux-navigator",
  dependencies = { "paulbkim-dev/vim-herdr-navigation" },
  lazy = false,
  init = function() vim.g.tmux_navigator_no_mappings = 1 end,
  config = function()
    local root = require("lazy.core.config").options.root
    local hook = root .. "/vim-herdr-navigation/editor/nvim.lua"
    if (vim.uv or vim.loop).fs_stat(hook) then
      dofile(hook)
    else
      vim.notify("vim-herdr-navigation not synced; run :Lazy sync", vim.log.levels.WARN)
    end
    -- The port has no "previous" action; keep tmux's <c-\> via the still-defined command.
    vim.keymap.set("n", "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>", { silent = true })
  end,
}
```

`vim.g.tmux_navigator_no_mappings = 1` disables only the *key maps*, not the
`TmuxNavigate*` *commands* — so the `$TMUX` fallback and `<c-\>` still resolve.

**3. Store `config.toml` as a direct Stow symlink — no base+generated pattern.**
herdr only writes `config.toml` once (the `onboarding` flag) and never rewrites
keys at runtime; runtime state lives in separate files (`session.json`,
`herdr.sock`, `herdr-client.sock`, `*.log`). This makes it unlike codex (whose
config.toml accretes trust entries and needs a `config.base.toml` + generated
gitignored file). One gotcha: herdr auto-creates a stub `config.toml` on first
run, so `rm -f ~/.config/herdr/config.toml` before `stow -t ~ herdr`, or Stow
refuses to overlay the non-symlink target.

## Why This Matters

- **Minimal override survives herdr upgrades.** Because unset keys inherit
  defaults, a herdr update that adds or retunes bindings flows through
  automatically; a full pasted keymap would silently pin stale defaults.
- **The plugin approach beats the two naive alternatives.** herdr's default
  `prefix+hjkl` loses the direct-key habit; raw direct `ctrl+hjkl` focus binds
  would steal the keys from vim/shell inside a pane. The process-aware plugin is
  the only option that preserves both muscle memory and in-pane vim navigation.
- **Direct-stow keeps the config a first-class tracked file** without a sync
  script, because herdr's runtime writes never touch it.

## When to Apply

- Adopting herdr (or re-evaluating its keymap) with existing tmux habits.
- Any multiplexer migration where the target tool merges user config over
  defaults — override the diff, not the whole map.
- Wiring vim-navigator-style navigation into a non-tmux multiplexer: look for a
  process-aware forwarder plugin rather than binding raw keys.

## Examples

tmux → herdr keymap actually shipped:

| Action | tmux | herdr |
|---|---|---|
| prefix | `C-s` | `ctrl+s` (override) |
| pane nav | `C-h/j/k/l` (vim-tmux-navigator) | direct `ctrl+h/j/k/l` (vim-herdr-navigation) |
| split stacked | `prefix s` | `prefix s` → `split_horizontal` (override) |
| split side-by-side | `prefix v` | `prefix v` → `split_vertical` (default) |
| settings | — | `prefix ,` (relocated) |
| copy-mode | `prefix [` | `prefix [` (herdr default already matches) |
| resize / reload / sidebar | — | `prefix r` / `R` / `b` (herdr defaults kept) |

Dropped in favor of herdr-native features: `prefix f` (tmux-sessionizer →
`workspace_picker`/`goto`), `prefix a`/`A` (tmux-attention → built-in agent
attention queue + notifications).

One assumption to verify on first launch: `split_vertical` is taken to produce a
side-by-side (right) pane and `split_horizontal` a stacked (below) pane. If the
geometry is reversed, swap the two `split_*` lines — a one-line fix.

## Related

- Design: `docs/superpowers/specs/2026-07-09-herdr-tmux-keybindings-design.md`
- Plan: `docs/superpowers/plans/2026-07-09-herdr-tmux-keybindings.md`
- Package convention + per-device setup: `CLAUDE.md` (`# herdr` section)
- Upstream: [herdr](https://herdr.dev), [vim-herdr-navigation](https://github.com/paulbkim-dev/vim-herdr-navigation)
