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

- `keys.json`: the TUI keymap, ported. `ctrl-h/j/k/l` run `vim-nav.*`.
  `ctrl-s` opens the `prefix` mod.
- `mods/vim-nav/`: vim-aware `ctrl-h/j/k/l` (a port of the
  `vim-herdr-navigation` plugin). The Neovim side is
  `nvim/.config/nvim/lua/herdr_navigation.lua`, which calls
  `herdr-app do pane.go` when `HC_TERMINAL_ID` is set.
- `mods/prefix/`: a popup that reads the key after `ctrl-s`: `s` split down,
  `v` split right, `,` settings.
- `layouts/vim-nav.json`: a clone of the shipped `main` layout with a hidden
  0px `vim-nav` block.

Herdr writes everything else (`settings.json`, `shared.json`, `view.json`,
`layouts/.state/`, `icons/`, `frame/`) and the shipped layouts and mods.
Keep those out of the package.

## Layout and mod depend on each other

A `<mod>.<command>` key reaches only a mod that the shown layout holds. If
the shown layout lacks the `vim-nav` block, `ctrl-h/j/k/l` fails with
`unknown command "vim-nav.left"`. Herdr replaces `main` on every start, so
the block lives in the `vim-nav` clone. Remove the layout and the mod
together.

A clone gets no updates from the shipped `main`. To pick them up, run
`herdr-app do layout.clone '{"name":"main","as":"vim-nav-new"}'`, add the
`vim-nav` block again, and replace `layouts/vim-nav.json`.

Structural window changes (sidebar side, panels, status bar, pane cards)
go into `layouts/vim-nav.json`. Look (theme, fonts, zoom) goes in
`settings.json`, which stays untracked.

## Stow with `--no-folding`

```sh
stow --no-folding -t ~ herdr-app
```

Without it, Stow links whole folders (`layouts/`, `mods/<name>/`) when they
do not exist yet. Herdr then writes `main.json`, `.state/` and mod type files
into the repo. `.gitignore` covers the mod type files (`gpui-kit.d.ts`,
`jsconfig.json`) as a backstop.

Herdr loads mods through symlinks. A mod edit through a Stow link may not
hot-reload: restart the app if the change does not show. Run
`herdr-app check herdr-app/.config/herdr-app/mods/<name>/` after each mod
edit.

## Per-device setup

1. `brew bundle --file=Brewfile` installs the cask. If an older
   `~/Applications/Herdr.app` exists, delete it and any
   `~/.local/bin/herdr-app` link to it first.
2. Launch Herdr once, so it creates `~/.config/herdr-app/`.
3. Delete the real copies of the tracked files in `~/.config/herdr-app/`.
   Stow refuses to overlay a real file.
4. `stow --no-folding -t ~ herdr-app`.
5. `herdr-app do layout.switch --name vim-nav`. Herdr saves the choice in
   `shared.json`.
