# herdr keybindings to match tmux muscle memory

Date: 2026-07-09
Status: Design approved, pending implementation

## Problem

herdr (`/opt/homebrew/bin/herdr`, homebrew-core, v0.7.x) is installed and
adopted as the primary agent workspace manager — the running session shows
Claude agents across `green-energy-group`, `ops`, and `dotfiles` workspaces.
herdr is a terminal workspace manager for AI coding agents: a tmux-style
multiplexer (workspaces / tabs / panes) with its own prefix-based keymap,
defaulting to prefix `ctrl+b`.

The muscle memory in the existing tmux config (`tmux/.config/tmux/tmux.conf`)
diverges from herdr's defaults. Goal: make herdr feel like tmux so no relearning
is needed. This is interpretation **A** — herdr replaces tmux as the day-to-day
driver (tmux config stays intact and keeps working, including inside/outside
herdr via the navigation fallback).

## Scope

Remap only the keys that diverge; keep herdr defaults where they were explicitly
accepted. Package the config into the dotfiles repo as a new Stow package and add
the Homebrew formula. Wire the seamless pane-navigation port into the existing
nvim config.

Out of scope: herdr theming (already `catppuccin` by default), notifications,
remote/SSH, worktree directory config, the codex↔herdr integration files
(`codex/.codex/herdr-agent-state.sh`, `hooks.json`) which herdr manages itself.

## Decisions (resolved during brainstorming)

- **End state**: A — herdr replaces tmux; make herdr's keys match tmux.
- **prefix**: `ctrl+s` (tmux prefix), overriding herdr's `ctrl+b`.
- **`r` / `R` / `b`**: keep herdr defaults — `prefix r` = resize_mode,
  `prefix R` = reload_config, `prefix b` = toggle_sidebar. (User does not use
  break-pane, so ceding `prefix b` to the sidebar is fine.)
- **Splits**: honor tmux muscle memory — `prefix s` = stacked (pane below),
  `prefix v` = side-by-side (pane right). Move herdr's `settings` off `prefix s`
  to `prefix ,` (comma).
- **`f` / `a`**: use herdr-native equivalents; drop the custom
  `tmux-sessionizer` / `tmux-attention` bindings. herdr provides
  `workspace_picker` (`prefix w`), `goto` (`prefix g`), and a built-in agent
  attention queue + notifications in the sidebar.
- **Pane navigation**: install the community port
  [`paulbkim-dev/vim-herdr-navigation`](https://github.com/paulbkim-dev/vim-herdr-navigation)
  to get direct `ctrl+h/j/k/l` (exact tmux muscle memory) that also works inside
  vim — the best of both. Chosen over herdr's default `prefix h/j/k/l` (loses the
  direct keys) and over raw direct `ctrl+hjkl` focus binds (would steal the keys
  from vim/shell inside a pane).
- **Packaging**: new `herdr/` Stow package, `config.toml` direct-stowed; add
  `brew "herdr"` to the Brewfile.

## Background research

herdr's own best-practice guidance (from `herdr --default-config` and
[docs](https://herdr.dev/docs/configuration#keybindings)): "The default keymap is
prefix-first and avoids direct shortcuts that can steal input from shells,
editors, tmux, or terminal apps." Direct chords (`ctrl+letter`, function keys)
are the most reliable when used; `alt+…`, `cmd`/`super`, and
punctuation-with-modifiers can depend on the outer terminal/tmux.

herdr merges `config.toml` with its built-in defaults, so `[keys]` needs only the
overridden entries, not the full keymap (docs: "A small keybinding override looks
like this").

`config.toml` is safe to direct-stow: herdr only writes it once (the `onboarding`
flag). Runtime state lives in separate files (`session.json`, `herdr.sock`,
`herdr-client.sock`, `*.log`) which are never stowed. `herdr config reset-keys`
(a manual command, not run automatically) is the only other writer, and it backs
up before rewriting.

### vim-herdr-navigation mechanism

`vim-tmux-navigator` ported to herdr's CLI. A herdr `plugin_action` binds
`ctrl+h/j/k/l`; on each press the action checks the focused pane's foreground
process via `herdr pane process-info`. If it is vim/neovim it forwards the key
into the pane with `herdr pane send-keys` (vim's own split-nav mappings then
move); otherwise it moves herdr focus with `herdr pane focus --direction`. The
editor side falls back to tmux (when `$TMUX` is set) or plain `wincmd` when not in
a herdr pane, so the existing tmux setup keeps working — `vim-tmux-navigator` does
not need to be removed.

## tmux → herdr keymap (final)

| Action | Key | Source |
|---|---|---|
| prefix | `ctrl+s` | remap (tmux) |
| pane nav (left/down/up/right) | direct `ctrl+h/j/k/l` | vim-herdr-navigation plugin |
| split stacked (pane below) | `prefix s` → `split_horizontal` | remap (tmux) |
| split side-by-side (pane right) | `prefix v` → `split_vertical` | herdr default, matches |
| settings | `prefix ,` (comma) | moved off `s` |
| new tab | `prefix c` → `new_tab` | herdr default, matches |
| copy-mode | `prefix [` → `copy_mode` | herdr default, already matches tmux |
| resize mode | `prefix r` → `resize_mode` | herdr default (kept) |
| reload config | `prefix R` → `reload_config` | herdr default (kept) |
| toggle sidebar | `prefix b` → `toggle_sidebar` | herdr default (kept) |
| workspace picker | `prefix w` → `workspace_picker` | herdr-native (replaces sessionizer) |
| goto | `prefix g` → `goto` | herdr-native |
| attention | sidebar queue + notifications | herdr-native (replaces tmux-attention) |

Dropped from tmux muscle memory (superseded by herdr-native features):
`prefix f` (tmux-sessionizer), `prefix a` / `prefix A` (tmux-attention),
`prefix b` = break-pane.

## Artifacts

### 1. `herdr/.config/herdr/config.toml` (new Stow package)

Minimal override — herdr merges the rest from its defaults.

```toml
onboarding = false

[keys]
prefix = "ctrl+s"
split_horizontal = "prefix+s"   # stacked (pane below): tmux muscle memory
settings = "prefix+comma"       # evicted from prefix+s

# vim-herdr-navigation: direct ctrl+hjkl, forwards into vim when vim is focused,
# else moves herdr pane focus; falls back to tmux/wincmd outside herdr.
[[keys.command]]
key = "ctrl+h"
type = "plugin_action"
command = "vim-herdr-navigation.left"
description = "navigate left (vim/herdr)"

[[keys.command]]
key = "ctrl+j"
type = "plugin_action"
command = "vim-herdr-navigation.down"
description = "navigate down (vim/herdr)"

[[keys.command]]
key = "ctrl+k"
type = "plugin_action"
command = "vim-herdr-navigation.up"
description = "navigate up (vim/herdr)"

[[keys.command]]
key = "ctrl+l"
type = "plugin_action"
command = "vim-herdr-navigation.right"
description = "navigate right (vim/herdr)"
```

`split_vertical` is left at its default (`prefix+v`) and so is not listed.

### 2. `nvim/.config/nvim/lua/plugins/nav.lua` (edit existing spec)

The file currently declares `christoomey/vim-tmux-navigator` (lines ~73-85) with
`<C-h/j/k/l>` mapped to `TmuxNavigate*`. Fold the port in: disable
vim-tmux-navigator's built-in mappings, add the port as a dependency so lazy.nvim
fetches it, and load `editor/nvim.lua` from lazy's install root (no hardcoded
checkout path) so the port owns `<C-h/j/k/l>` as the single source of truth.

```lua
{
  "christoomey/vim-tmux-navigator",
  dependencies = { "paulbkim-dev/vim-herdr-navigation" },
  lazy = false,
  init = function()
    vim.g.tmux_navigator_no_mappings = 1
  end,
  config = function()
    local root = require("lazy.core.config").options.root
    dofile(root .. "/vim-herdr-navigation/editor/nvim.lua")
  end,
}
```

The port's editor side keeps the tmux/`wincmd` fallback, so the existing
`TmuxNavigate*` behavior still applies when running under tmux or outside herdr.

### 3. `Brewfile`

Add `brew "herdr"` in alphabetical order (homebrew-core, no tap).

### 4. Setup steps (documented, not all Stow-managed)

herdr plugins install into herdr's own plugin store (not `~/.config/herdr` and
not Stow-managed), analogous to `tpm` for tmux. Document these as one-time
per-device steps in the `herdr/` package README or repo docs:

1. `brew bundle --file=Brewfile` — installs herdr from homebrew-core.
2. `herdr plugin install paulbkim-dev/vim-herdr-navigation --yes` — registers the
   `vim-herdr-navigation.*` plugin actions the config references.
3. `mkdir -p ~/.config/herdr` then `stow -t ~ herdr` — symlink `config.toml`.
4. Launch nvim once so lazy.nvim syncs `vim-herdr-navigation`.
5. `herdr server reload-config` (or restart the herdr server) to load the keys.

### 5. Documentation

`ce-compound` solution doc in `docs/solutions/` capturing the herdr↔tmux keymap
and the vim-herdr-navigation trick. `wiki-stage` mirrors it into
`~/workspace/wiki/raw/dotfiles/` for later ingest.

## Verification

- `herdr --default-config` diffed against the stowed `config.toml` to confirm only
  the intended keys are overridden.
- After `stow -t ~ herdr` + `herdr server reload-config`: manually exercise
  `prefix s` (stacked split), `prefix v` (side-by-side split), `prefix ,`
  (settings), and `ctrl+h/j/k/l` navigation both inside nvim (moves vim splits,
  falls through at edges) and between plain shell panes.
- `herdr plugin action list --plugin vim-herdr-navigation` shows the four
  `.left/.down/.up/.right` actions.
- Confirm the `config.toml` symlink resolves into the repo and herdr has not
  rewritten it.

## Risks / things to verify on first use

- **Split axis assumption**: herdr `split_vertical` is assumed to produce
  side-by-side (new pane right) and `split_horizontal` stacked (new pane below),
  matching vim/zellij/wezterm convention and herdr's `--direction right|down`
  CLI. If first launch shows the geometry reversed, swap the two `split_*` lines
  — a one-line fix. This is the only unverified mapping.
- **`ctrl+l` in a shell**: now navigates-right (the plugin forwards to vim only
  when vim is the focused process), replacing the shell's clear-screen. This is
  the same tradeoff already accepted under vim-tmux-navigator in tmux, where the
  tmux config rebinds `prefix C-l` to resend `C-l`. No change in habit.
- **Plugin availability**: the config references `vim-herdr-navigation.*` plugin
  actions; if the herdr plugin is not installed, those `ctrl+hjkl` binds no-op.
  Step 2 of setup covers this; the risk is only on a fresh device where the step
  is skipped.
