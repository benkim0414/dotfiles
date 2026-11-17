---
paths:
  - "nvim/**"
---

# Neovim

## Treesitter parser compilation

`nvim-treesitter` compiles parsers with a C compiler. The config uses a valid
`CC` first. Otherwise it finds `cc`, `gcc`, `clang`, or a Homebrew-style
`gcc-*` on `PATH` and exports `CC` before parser builds.

- macOS: `brew bundle --file=Brewfile` installs Homebrew `gcc` (`gcc-15` and
  similar). Apple's Command Line Tools also provide `cc`.
- Fedora: `sudo dnf install gcc`
- Debian/Ubuntu: `sudo apt install build-essential`

Verify with `nvim --headless "+TSInstallSync json" +qa`.

## herdr navigation (`lua/herdr_navigation.lua`)

The `vim-tmux-navigator` spec in `lua/plugins/nav.lua` loads
`require("herdr_navigation").setup()`. That file is a pinned copy of upstream
`vim-herdr-navigation` `editor/nvim.lua` at `7873100`, including the desktop
`HC_TERMINAL_ID` / `herdr-app do pane.go --direction` branch.

- The one behavioural delta: each TUI handoff validates the executable. A
  usable `HERDR_BIN_PATH` wins, else `exepath("herdr")`. It warns only when
  neither is usable. Launched commands keep upstream's quiet exit handling.
- The lazy dependency on `vim-herdr-navigation` exists for
  `herdr plugin link` only. Load the editor code from the pinned copy, never
  with `dofile` of the lazy checkout: Lazy sync does not update the copy.
- To refresh the copy: compare with upstream, keep the executable check,
  update the provenance comment, then run
  `nvim --headless -u NONE -i NONE -l nvim/tests/herdr_navigation.lua` from
  the repo root.
- `nvim/.stow-local-ignore` keeps `nvim/tests/` out of `~/tests`.
