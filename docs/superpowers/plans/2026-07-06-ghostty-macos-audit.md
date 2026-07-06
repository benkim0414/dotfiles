# Ghostty macOS Config Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bare, omarchy-broken ghostty config with a mac-only Catppuccin Mocha config tuned for a tmux + Claude Code workflow.

**Architecture:** Single stow-symlinked config file (`ghostty/.config/ghostty/config`) is overwritten with a self-contained macOS config. No new files. Omarchy include removed.

**Tech Stack:** Ghostty 1.3.1, GNU Stow, macOS.

## Global Constraints

- Mac-only. No omarchy include, no cross-platform conditionals.
- Theme must be the built-in `Catppuccin Mocha` (resources), never the untracked user file `~/.config/ghostty/themes/catppuccin-mocha`.
- Only option names/values verified against `ghostty +show-config --default` on 1.3.1 are used.

---

### Task 1: Rewrite ghostty config

**Files:**
- Modify: `ghostty/.config/ghostty/config` (full overwrite, currently 3 lines)

**Interfaces:**
- Consumes: nothing.
- Produces: the live config at `~/.config/ghostty/config` (already symlinked via stow).

- [ ] **Step 1: Overwrite the config file**

Write exactly:

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

- [ ] **Step 2: Verify ghostty parses it with no errors**

Run: `ghostty +show-config 2>&1 | grep -iE "theme|titlebar|option-as-alt|bell-features|window-padding|window-save-state|mouse-hide"`
Expected: values echo back as written (theme = Catppuccin Mocha, macos-titlebar-style = hidden, macos-option-as-alt = true, bell-features includes system+attention+title, window-padding-x/y = 8, window-padding-balance = true, window-save-state = always, mouse-hide-while-typing = true). No parse-error lines on stderr.

- [ ] **Step 3: Commit**

```bash
git add ghostty/.config/ghostty/config
git commit -m "feat(ghostty): mac-only Catppuccin Mocha config"
```

---

### Task 2: Manual launch verification

**Files:** none.

- [ ] **Step 1: Launch a new ghostty window**

Confirm by eye: Catppuccin Mocha colors render (dark base, mauve accent), titlebar hidden, ~8px padding around the grid, no error banner on startup.

- [ ] **Step 2: Confirm tmux interop unbroken**

Inside tmux: `S-arrow` resizes a pane, Claude Code Shift+Enter inserts a newline, copy-mode yank lands in the macOS clipboard (OSC 52).

- [ ] **Step 3: No commit**

Verification only.
```
