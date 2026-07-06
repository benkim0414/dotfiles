# Ghostty macOS config audit

Date: 2026-07-06

## Problem

Ghostty on this Mac runs bare defaults. The config's only include points at an
omarchy Linux theme path (`?~/.config/omarchy/current/theme/ghostty.conf`) that
does not exist on macOS. The `?` prefix makes the include optional, so ghostty
silently falls back to defaults: no Catppuccin theme, no macOS tuning. Every
other tool in the dotfiles is themed Catppuccin Mocha mauve (BAT_THEME, lazygit,
gh-dash, tmux) — ghostty is the lone exception.

The user no longer runs omarchy, so the config becomes mac-only. The omarchy
include is dead weight and is removed.

## Environment

- Ghostty 1.3.1 (Homebrew, `/opt/homebrew/bin/ghostty`).
- Config is a live stow symlink: `~/.config/ghostty/config` ->
  `ghostty/.config/ghostty/config`.
- Workflow: tmux-heavy (prefix `C-s`, vi mode, splits, sessionizer, unprefixed
  `S-arrow`/`C-arrow` resize, `monitor-bell on`, OSC 52 clipboard, extended-keys
  for Claude Code Shift+Enter, OSC 777 desktop notifications via
  `allow-passthrough all`) + git worktrees + Claude Code.
- A stray untracked theme file exists at `~/.config/ghostty/themes/catppuccin-mocha`
  (Oct 2025, omarchy-era leftover). Not in the repo, not stowed. The design
  deliberately does NOT depend on it.

## Decisions (user-confirmed)

- Scope: full audit, mac-only, omarchy dropped.
- Background: opaque (`background-opacity = 1`), no blur.
- Titlebar: `hidden`.
- `macos-option-as-alt = true`.
- Quick-terminal dropdown: skipped.

## Target config

Full contents of `ghostty/.config/ghostty/config` after the change:

```
# Font
font-family = JetBrainsMonoNL Nerd Font
font-size = 16

# Theme — built-in Catppuccin Mocha (self-contained, no stray files)
theme = Catppuccin Mocha

# macOS
macos-titlebar-style = hidden
macos-option-as-alt = true
window-save-state = always

# Window
window-padding-x = 8
window-padding-y = 8
window-padding-balance = true
background-opacity = 1

# Behavior
mouse-hide-while-typing = true

# Bell — native notification on bell (attention+title already default)
bell-features = system,attention,title
```

## Rationale (per setting)

- **theme = Catppuccin Mocha** — the core fix. Uses the built-in (`resources`)
  theme, not the untracked user file `catppuccin-mocha`, so it survives a fresh
  stow on any machine.
- **macos-titlebar-style = hidden** — tmux owns windows/tabs; native ghostty
  tabs are wasted vertical space. Default is `transparent`.
- **macos-option-as-alt = true** — Option sends Meta/Esc for nvim/zsh word
  motions and tmux meta binds. Tradeoff: Option no longer types accented chars.
  Default is empty (off).
- **window-save-state = always** — reopen restores windows. Default `default`.
- **window-padding-x/y = 8, window-padding-balance = true** — breathing room vs
  the default `2`; balance keeps even margins when the cell grid does not divide
  the window cleanly.
- **background-opacity = 1** — opaque, per decision. (Explicit, though it equals
  the default, to document the choice.)
- **mouse-hide-while-typing = true** — cursor out of the way while typing.
  Default `false`.
- **bell-features = system,attention,title** — `attention` (dock bounce) and
  `title` (title flash) are already default; the added value is `system`, which
  fires a native macOS notification on bell even when ghostty is hidden or
  unfocused. Pairs with tmux `monitor-bell on` and the tmux-attention workflow
  for the "walked away, Claude needs input" case.

## Non-changes / considerations

- Default cmd/super keybinds are kept. They do not clash with tmux ctrl/meta
  bindings.
- Ghostty's default `shift+arrow = adjust_selection` only fires when a selection
  is active, so the tmux `S-arrow` resize binding still reaches tmux. No override
  needed. Flagged as a known-checked item.
- The stray `~/.config/ghostty/themes/catppuccin-mocha` file is left as-is —
  harmless once the built-in theme is used.
- No quick-terminal, no transparency/blur, no font changes.

## Verification

- `stow -t ~ -R ghostty` (config is already symlinked; re-stow is a no-op safety).
- `ghostty +show-config 2>/dev/null | grep -iE "theme|titlebar|option-as-alt|bell-features|window-padding|window-save-state|mouse-hide"`
  confirms values are parsed as written.
- Launch ghostty: verify Catppuccin Mocha colors render, titlebar is hidden,
  padding visible, no parse errors on startup.
- Confirm tmux still works: `S-arrow` resize, Claude Code Shift+Enter, copy via
  OSC 52.
```
