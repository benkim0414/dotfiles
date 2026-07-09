# Herdr Starship and Plugin Fix Design

## Problem

After installing Herdr and stowing the dotfiles, Herdr panes do not show the
Starship prompt and the `vim-herdr-navigation` keybindings do not work.

Investigation found two separate runtime causes:

- The focused Herdr pane is running `/bin/bash`, so `zsh/.zshrc` is not sourced
  and `starship init zsh` never runs.
- `herdr plugin list --json` reports an empty plugin registry, so the
  `vim-herdr-navigation.{left,down,up,right}` actions referenced by
  `herdr/.config/herdr/config.toml` are not registered.

The Herdr config is stowed correctly: `~/.config/herdr` points at the repo
package. Starship itself is installed, `~/.config/starship.toml` is stowed, and
an interactive zsh smoke test produces a Starship prompt.

## Design

Add an explicit Herdr terminal shell setting:

```toml
[terminal]
default_shell = "zsh"
shell_mode = "login"
```

This makes new Herdr panes start zsh even if the Herdr server was launched from
an environment whose `$SHELL` is missing or stale. Login mode keeps pane startup
aligned with normal terminal sessions.

Keep `vim-herdr-navigation` as a device-local Herdr plugin. The repo already
tracks the Herdr keybindings and the Neovim lazy.nvim dependency, but Herdr's
own plugin registry is outside Stow. Fix the current machine by linking the
existing lazy.nvim checkout:

```bash
herdr plugin link ~/.local/share/nvim/lazy/vim-herdr-navigation
```

The documented fresh-machine path remains:

```bash
herdr plugin install paulbkim-dev/vim-herdr-navigation --yes
```

## Verification

- Parse `herdr/.config/herdr/config.toml` as TOML and confirm
  `terminal.default_shell == "zsh"` and `terminal.shell_mode == "login"`.
- Run `herdr server reload-config` and expect `status = applied` with no
  diagnostics.
- Run `herdr plugin action list --plugin vim-herdr-navigation` and expect
  actions ending in `.left`, `.down`, `.up`, and `.right`.
- Create or restart a Herdr pane and confirm `herdr pane process-info --current`
  reports zsh as the pane shell or foreground process before launching other
  commands.
