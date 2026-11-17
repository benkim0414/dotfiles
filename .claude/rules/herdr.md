---
paths:
  - "herdr/**"
---

# herdr

herdr (`brew "herdr"`) is the primary agent workspace manager. The package
ships `~/.config/herdr/config.toml`.

## Keymap

The config maps herdr onto tmux muscle memory:

- Prefix `ctrl+s`. `prefix s` = stacked split, `prefix ,` = settings
  (herdr's default for `prefix s`). `prefix v` (side-by-side split), `r`,
  `R` and `b` keep herdr defaults.
- Navigate mode: `j`/`k` move the workspace sidebar
  (`navigate_workspace_up/down`). Up/down arrows move pane focus
  (`navigate_pane_up/down`).
- `ctrl+h/j/k/l` comes from the `vim-herdr-navigation` herdr plugin (a
  vim-tmux-navigator port). It forwards the key into a focused vim pane, else
  moves herdr focus, and falls back to tmux or `wincmd` outside herdr. The
  Neovim side is in `nvim/` (see its rule).

New panes launch zsh as a login shell, so the stowed zsh config and Starship
load even when the herdr server started from a sparse environment.

## Config writes

`config.toml` is direct-stowed, and herdr writes to it through the symlink.
As of herdr 0.9.5 (`src/config/write.rs`), it writes:

- `onboarding = false` after onboarding.
- From the settings overlay: `[theme] name` (and `auto_switch = false`),
  `[ui] status_indicators`, `[ui.sound] enabled`, `[ui.toast] delivery`.

These writes land in the repo. Commit the ones worth keeping and
`git checkout` the rest. Other runtime state (sidebar preferences,
`session.json`, `plugins.json`, sockets, logs) lives in separate files.

## Per-device setup

1. `brew bundle --file=Brewfile` installs herdr.
2. `herdr plugin install paulbkim-dev/vim-herdr-navigation --yes` registers
   the `vim-herdr-navigation.*` actions that the `ctrl+hjkl` binds call. If
   lazy.nvim already cloned it, `herdr plugin link
   ~/.local/share/nvim/lazy/vim-herdr-navigation` also works. herdr plugins
   live in herdr's own store, outside Stow (like `tpm` for tmux).
3. `rm -f ~/.config/herdr/config.toml`, then `stow -t ~ herdr`. herdr creates
   an `onboarding` stub on first run, and Stow refuses to overlay a
   non-symlink.
4. Launch nvim once so lazy.nvim syncs `vim-herdr-navigation`.
5. `herdr server reload-config` (or restart the server) to load the keys.
