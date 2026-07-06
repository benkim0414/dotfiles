---
title: "Ghostty macOS config: optional includes fail silently; prefer built-in theme names"
date: 2026-07-06
category: tooling-decisions
module: ghostty
problem_type: tooling_decision
component: tooling
severity: low
applies_when:
  - "Editing the stowed ghostty config on macOS"
  - "A ghostty config-file include points at a path that may not exist on every machine"
  - "Theming ghostty to match a Catppuccin/other themed toolchain"
  - "Running ghostty as the host terminal for a tmux + Claude Code workflow"
tags: [ghostty, terminal, macos, tmux, catppuccin, config, stow]
---

# Ghostty macOS config: optional includes fail silently; prefer built-in theme names

## Context

The stowed ghostty config carried a single line inherited from an omarchy
(Arch/Hyprland) setup:

```
config-file = ?~/.config/omarchy/current/theme/ghostty.conf
```

On macOS that path does not exist. The `?` prefix marks the include *optional*,
so ghostty loads nothing from it and emits no warning. The net effect: ghostty
ran on bare defaults — no Catppuccin theme, no macOS tuning — while every other
tool in the repo (BAT_THEME, lazygit, gh-dash, tmux) was themed Catppuccin
Mocha. The breakage was invisible because the mechanism designed to tolerate a
missing file also hides that the file is missing.

## Guidance

- Do not rely on a `?`-optional `config-file` include for load-bearing config
  (like the theme) unless you have confirmed the target resolves on the machine
  you are on. Optional includes are for genuinely optional overlays, not for the
  primary path.
- Prefer a **built-in theme name** over an include of an external theme file:

  ```
  theme = Catppuccin Mocha
  ```

  This resolves the theme from ghostty's bundled `resources`, so it is
  self-contained and survives a fresh `stow` on any machine. Ghostty also
  matched a lowercase `catppuccin-mocha (user)` entry from a stray untracked
  file in `~/.config/ghostty/themes/`; naming the built-in `Catppuccin Mocha`
  avoids depending on that leftover.
- Verify a config parses without launching the GUI by pointing ghostty at an
  isolated config dir (the `--config-file` flag is a no-op for `+show-config`):

  ```sh
  TMP="$(mktemp -d)"; mkdir -p "$TMP/ghostty"
  cp <config> "$TMP/ghostty/config"
  XDG_CONFIG_HOME="$TMP" ghostty +show-config 2>/dev/null | grep -iE "theme|titlebar|bell-features"
  ```

  A correct theme resolves to its palette (Catppuccin Mocha shows
  `background = #1e1e2e`, `foreground = #cdd6f4`), which confirms the theme was
  found, not just accepted.
- Discover exact option names/values/defaults from the installed binary rather
  than guessing: `ghostty +show-config --default` and
  `ghostty +list-themes`.

### macOS + tmux tuning that this config settled on

```
macos-titlebar-style = hidden      # tmux owns tabs/windows; reclaim vertical space
macos-option-as-alt  = true        # Option -> Meta/Esc for nvim/zsh; loses accented chars
window-save-state    = always
window-padding-x = 8
window-padding-y = 8
window-padding-balance = true      # even margins when the cell grid doesn't divide evenly
mouse-hide-while-typing = true
bell-features = system,attention,title
```

Notes on the non-obvious ones:

- `bell-features`: `attention` (dock bounce) and `title` (title flash) are
  **already default** (`no-system,no-audio,attention,title,no-border`). The only
  thing this line adds is `system` — a native macOS notification on bell, which
  surfaces even when ghostty is hidden. Pairs with tmux `monitor-bell on` and
  Claude Code's OSC 777 for "walked away, Claude needs input".
- `macos-titlebar-style = hidden` keeps the window frame and rounded corners
  (unlike `window-decoration = none`), so the window is still draggable. It does
  force the traffic-light buttons off; close/minimize stay reachable via the
  menu bar and `super+q` / `super+w`.

## Why This Matters

A silently-ignored optional include is the worst kind of config bug: no error,
no crash, just quietly-wrong behavior that persists until someone notices the
colors don't match. Making the theme self-contained (built-in name, no external
include) removes the failure mode entirely and makes the config reproducible
across machines via stow alone.

## When to Apply

- When a ghostty config include points at a machine-specific or
  distro-specific path.
- When theming ghostty to match the rest of a themed toolchain.
- Before assuming a config change took effect — verify the parsed output, don't
  trust the absence of an error.

## Examples

Before (bare defaults on macOS — the include silently no-ops):

```
config-file = ?~/.config/omarchy/current/theme/ghostty.conf
font-family = JetBrainsMonoNL Nerd Font
font-size = 14
```

After (self-contained, mac-only):

```
font-family = JetBrainsMonoNL Nerd Font
font-size = 16
theme = Catppuccin Mocha
macos-titlebar-style = hidden
macos-option-as-alt = true
window-save-state = always
window-padding-x = 8
window-padding-y = 8
window-padding-balance = true
background-opacity = 1
mouse-hide-while-typing = true
bell-features = system,attention,title
```

## tmux interop (verified against Ghostty 1.3.1 source)

These held up under source review and are worth not re-litigating:

- **`shift+arrow` pane resize passes through to tmux.** Ghostty's default
  `shift+arrow = adjust_selection` binds are `.performable = true`, so with no
  active text selection the key is not consumed and reaches tmux. (Only when a
  mouse selection is active does Shift+Arrow adjust the selection instead.)
- **`C-s` prefix and `Ctrl+Arrow`** are unbound in ghostty defaults → pass
  straight through.
- **Shift+Enter (Claude Code)** rides the Kitty keyboard protocol, which
  ghostty negotiates automatically on app request — no config key exists or is
  needed. Do not invent an `extended-keys` ghostty option; it does not exist and
  will fail to parse. (That option lives in *tmux*, not ghostty.)
- **OSC 52** clipboard works because `clipboard-write` defaults to `allow`;
  **OSC 777** notifications work because `desktop-notifications` defaults to
  `true`.

## Related

- `docs/solutions/integration-issues/tmux-attention-no-alert-on-askuserquestion.md`
- Spec: `docs/superpowers/specs/2026-07-06-ghostty-macos-audit-design.md`
