---
paths:
  - "herdr-app/**"
---

# herdr-app

herdr-app (`cask "herdr-app"`) is the Herdr desktop app. The herdr TUI is a
separate package (`herdr/`). The Herdr team's guide ships in the app's home as
`~/.config/herdr-app/AGENTS.md`. Read it before you change a layout, mod or
key.

## What the package tracks

Only files the person owns:

- `keymaps/{macos,linux}/`: native Herdr App v0.1.16 shortcuts plus the
  shared `ctrl-s` opener and `vim-nav` bindings. Herdr reads one `keys.json`
  and does not merge custom files with its defaults. When upgrading, compare
  each map with the new platform defaults before adding changed bindings.
- `mods/vim-nav/`: vim-aware `ctrl-h/j/k/l` (a port of the
  `vim-herdr-navigation` plugin). The Neovim side is
  `nvim/.config/nvim/lua/herdr_navigation.lua`, which calls
  `herdr-app do pane.go` when `HC_TERMINAL_ID` is set.
- `mods/prefix/`: shared TUI-style shortcuts. `Shift+n` creates a space,
  `c` creates a tab, `s` and `v` split panes, and `,` opens settings.
  `w` opens space navigation: `1`–`9` jump by position and close the overlay.
  `j` or `n` selects the next space. `k` or `p` selects the previous space.
  `gg`/`G` switch to the first/last space. `Esc` closes the overlay.
  `/` opens the original picker.
  `b` collapses or expands the sidebar. The native direct shortcuts
  (`Cmd+B` on macOS and `Ctrl+Shift+B` on Linux) still hide or show it.
- `layouts/vim-nav.json`: a clone of the shipped `main` layout with a hidden
  0px `vim-nav` block.

Herdr writes everything else (`settings.json`, `shared.json`, `view.json`,
`layouts/.state/`, `icons/`, `frame/`) and the shipped layouts and mods.
Keep those out of the package.

## Layout and mod depend on each other

A `<mod>.<command>` key reaches only a mod that the shown layout holds.
Bind `ctrl-h/j/k/l` in `layout:vim-nav` so they work only in that layout and
do not try to call a missing mod elsewhere. The prefix works in any layout.
The block lives in a clone because Herdr owns the shipped `main` layout.

A clone gets no updates from the shipped `main`. To pick them up, run
`herdr-app do layout.clone '{"name":"main","as":"vim-nav-new"}'`, add the
`vim-nav` block again, and replace `layouts/vim-nav.json`.

Structural window changes (sidebar side, panels, status bar, pane cards)
go into `layouts/vim-nav.json`. Look (theme, fonts, zoom) goes in
`settings.json`, which stays untracked.

## Install with Stow

From the main checkout, use the wrapper to select the platform keymap and
check both packages for conflicts before linking either one:

```sh
bash herdr-app/install.sh --dry-run
bash herdr-app/install.sh
```

Alternatively, use plain Stow. Select `macos` or `linux` explicitly and use
`-n` on both commands first to check for conflicts:

```sh
stow --no-folding -t ~ herdr-app
stow --no-folding -d herdr-app/keymaps -t ~ macos
```

To remove both sets of links, use `bash herdr-app/install.sh --delete`.
Neither method installs a second copy of the app or changes device settings.

Without `--no-folding`, Stow links whole folders (`layouts/`, `mods/<name>/`)
when they do not exist yet. Herdr then writes `main.json`, `.state/` and mod
type files into the repo. Stow and Git ignore the generated mod type files.

Herdr loads mods through symlinks. A mod edit through a Stow link may not
hot-reload: restart the app if the change does not show. Run
`herdr-app check herdr-app/.config/herdr-app/mods/<name>/` after each mod
edit.

## Per-device setup

1. On macOS, install with `brew bundle --file=Brewfile` or keep your existing
   Herdr App installation. On Linux, use the
   [official download](https://herdr.dev/download/).
2. Quit Herdr App and preview the Stow links. Back up and move only the
   conflicting files reported in the preview, usually `keys.json`.
   If you already stowed the old keymap, its `keys.json` link can be dangling
   after this update. Move that link aside and rerun the preview. Leave the
   other Stow links in place.
3. Install from the main checkout and open the app.
4. To enable Vim-aware navigation, run `herdr-app do layout.switch --name vim-nav`.
   Herdr saves the choice in `shared.json`.
