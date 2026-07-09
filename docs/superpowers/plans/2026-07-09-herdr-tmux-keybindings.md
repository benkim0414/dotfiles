# herdr tmux-muscle-memory Keybindings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure herdr so its keymap matches the existing tmux muscle memory, packaged into the dotfiles repo.

**Architecture:** A new `herdr/` Stow package ships a minimal `config.toml` that overrides only the diverging keys (herdr merges the rest from its built-in defaults). Direct `ctrl+h/j/k/l` pane navigation comes from the `vim-herdr-navigation` herdr plugin (installed into herdr's own plugin store) plus its editor hook folded into the existing nvim `vim-tmux-navigator` spec. The Brewfile gains the homebrew-core `herdr` formula, and CLAUDE.md documents the package + one-time setup steps.

**Tech Stack:** herdr (homebrew-core, v0.7.x, TOML config), GNU Stow, Homebrew Brewfile, Neovim + lazy.nvim (Lua), the `paulbkim-dev/vim-herdr-navigation` herdr plugin.

## Global Constraints

- Config is a **minimal override**: `[keys]` lists only changed entries; never paste herdr's full default keymap. (spec: herdr merges config.toml with defaults)
- `config.toml` is **direct-stowed** (herdr only writes the `onboarding` flag, never rewrites keys at runtime); do NOT use a base+generated pattern.
- Brewfile entries stay **alphabetically sorted**; CLI tools use `brew "<name>"`.
- **Atomic commits**, one logical change each; stage specific files only (never `git add -A`/`.`/`-u`). Conventional commits: `type(scope): description`. Scope for all commits here: `herdr`.
- Stow **always** with `-t ~`.
- Split-axis mapping (`split_vertical` = side-by-side / `split_horizontal` = stacked) is the one assumption to confirm at first use; a reversal is a one-line swap.

---

### Task 1: herdr Stow package + config.toml

**Files:**
- Create: `herdr/.config/herdr/config.toml`

**Interfaces:**
- Produces: the `vim-herdr-navigation.{left,down,up,right}` plugin-action references consumed by Task 3 (plugin install) and Task 4 (nvim side). Action names must match exactly.

- [ ] **Step 1: Create the config file**

Create `herdr/.config/herdr/config.toml`:

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

- [ ] **Step 2: Remove the live regular file so Stow can link (identical content)**

The live `~/.config/herdr/config.toml` is a plain file containing only
`onboarding = false` — a strict subset of the new file, so nothing is lost.
Stow refuses to overlay a non-symlink target, so remove it first:

Run:
```bash
cat ~/.config/herdr/config.toml   # confirm it is only: onboarding = false
rm ~/.config/herdr/config.toml
```
Expected: the `cat` prints `onboarding = false` and nothing else before removal.

- [ ] **Step 3: Dry-run the stow to preview the symlink**

Run: `stow -n -v -t ~ herdr`
Expected: output shows `LINK: .config/herdr/config.toml => ../../workspace/dotfiles/herdr/.config/herdr/config.toml` (or equivalent relative path) and no conflict lines. The `~/.config/herdr` directory already exists (holds runtime sockets/logs), so Stow links the single file into it rather than tree-folding the directory.

- [ ] **Step 4: Apply the stow**

Run: `stow -t ~ herdr`
Then verify the symlink resolves into the repo:
Run: `readlink -f ~/.config/herdr/config.toml`
Expected: path ends with `dotfiles/herdr/.config/herdr/config.toml` (or, when run from the worktree checkout, the worktree copy — either is acceptable during implementation).

- [ ] **Step 5: Confirm only intended keys are overridden**

Run:
```bash
herdr --default-config | grep -E '^(prefix|settings|split_horizontal|split_vertical) ='
```
Expected: shows herdr's defaults (`prefix = "ctrl+b"`, `settings = "prefix+s"`, `split_horizontal = "prefix+minus"`, `split_vertical = "prefix+v"`). Then eyeball the stowed file: only `prefix`, `split_horizontal`, `settings`, and the four `[[keys.command]]` blocks appear under `[keys]`. `split_vertical` is intentionally absent (kept at default).

- [ ] **Step 6: Reload herdr config (non-fatal if server not running)**

Run: `herdr server reload-config`
Expected: success message, or a "no server running" notice (fine — keys load on next launch). This must not error on malformed TOML; if it reports a parse error, fix the file before continuing.

- [ ] **Step 7: Commit**

```bash
git add herdr/.config/herdr/config.toml
git commit -m "feat(herdr): tmux-muscle-memory keymap in herdr config"
```

---

### Task 2: Add herdr to the Brewfile

**Files:**
- Modify: `Brewfile`

**Interfaces:**
- Consumes: nothing.
- Produces: `brew "herdr"` so `brew bundle` reinstalls herdr on a fresh device.

- [ ] **Step 1: Confirm herdr's current Brewfile absence and neighbors**

Run: `grep -n '^brew "h' Brewfile`
Expected: lists the `brew "h..."` block; note the alphabetical slot where `herdr` belongs (after `brew "h..."` entries that sort before `herdr`, before those after).

- [ ] **Step 2: Insert the entry alphabetically**

Add the line in the correct sorted position among the `brew "..."` entries:

```ruby
brew "herdr"
```

- [ ] **Step 3: Verify placement and that brew sees it as installed**

Run:
```bash
grep -n '^brew "herdr"$' Brewfile
brew list herdr >/dev/null && echo "herdr present"
```
Expected: the grep prints the new line; `herdr present` confirms the formula is already installed locally (so `brew bundle` will be a no-op on this device).

- [ ] **Step 4: Commit**

```bash
git add Brewfile
git commit -m "chore(herdr): add herdr formula to Brewfile"
```

---

### Task 3: Install the vim-herdr-navigation herdr plugin (device setup)

**Files:**
- None tracked in the repo (herdr installs into its own plugin store, analogous to `tpm` for tmux). No commit in this task.

**Interfaces:**
- Consumes: the `vim-herdr-navigation.{left,down,up,right}` action names referenced by Task 1's `config.toml`.
- Produces: the registered plugin actions those `ctrl+hjkl` binds invoke.

- [ ] **Step 1: Install the plugin from GitHub**

Run: `herdr plugin install paulbkim-dev/vim-herdr-navigation --yes`
Expected: install succeeds and prints a plugin id (`vim-herdr-navigation`).

- [ ] **Step 2: Verify the four navigation actions exist**

Run: `herdr plugin action list --plugin vim-herdr-navigation`
Expected: lists actions ending in `.left`, `.down`, `.up`, `.right`. These names must match the `command = "vim-herdr-navigation.*"` values in `config.toml`; if the plugin exposes different names, update `config.toml` to match and amend Task 1's commit.

- [ ] **Step 3: Reload and confirm the binds resolve**

Run: `herdr server reload-config`
Expected: no "unknown plugin action" warnings for the `ctrl+hjkl` binds. (No commit — this task changes only device-local herdr state.)

---

### Task 4: Fold vim-herdr-navigation into the nvim navigator spec

**Files:**
- Modify: `nvim/.config/nvim/lua/plugins/nav.lua:72-88`

**Interfaces:**
- Consumes: the herdr-side plugin from Task 3 at runtime (the editor hook calls `herdr pane ...` only when inside a herdr pane; otherwise it falls back to tmux/`wincmd`).
- Produces: `<C-h/j/k/l>` owned by the port as the single source of truth.

- [ ] **Step 1: Replace the vim-tmux-navigator block**

In `nvim/.config/nvim/lua/plugins/nav.lua`, replace this exact block (the third
plugin spec, lines 72-88):

```lua
  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
    },
    keys = {
      { "<c-h>",  "<cmd><C-U>TmuxNavigateLeft<cr>",     desc = "Navigate left" },
      { "<c-j>",  "<cmd><C-U>TmuxNavigateDown<cr>",     desc = "Navigate down" },
      { "<c-k>",  "<cmd><C-U>TmuxNavigateUp<cr>",       desc = "Navigate up" },
      { "<c-l>",  "<cmd><C-U>TmuxNavigateRight<cr>",    desc = "Navigate right" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>", desc = "Navigate previous" },
    },
  }
```

with:

```lua
  {
    "christoomey/vim-tmux-navigator",
    dependencies = { "paulbkim-dev/vim-herdr-navigation" },
    lazy = false,
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
    config = function()
      -- vim-herdr-navigation owns <C-h/j/k/l>: forwards to herdr when in a herdr
      -- pane, falls back to tmux ($TMUX) or plain wincmd otherwise.
      local root = require("lazy.core.config").options.root
      dofile(root .. "/vim-herdr-navigation/editor/nvim.lua")
    end,
  }
```

- [ ] **Step 2: Sync lazy so it fetches the port**

Run: `nvim --headless "+Lazy! sync" +qa`
Expected: completes and exits 0; `vim-herdr-navigation` is cloned. Confirm:
Run: `ls "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/vim-herdr-navigation/editor/nvim.lua"`
Expected: the path exists.

- [ ] **Step 3: Confirm nvim loads the spec without error**

Run: `nvim --headless "+lua vim.cmd('messages')" +qa 2>&1 | tail -20`
Expected: no Lua error mentioning `vim-herdr-navigation`, `nav.lua`, or `lazy.core.config`. A clean start (no error output) confirms the `dofile` path resolved and the module loaded.

- [ ] **Step 4: Commit**

```bash
git add nvim/.config/nvim/lua/plugins/nav.lua
git commit -m "feat(herdr): route nvim C-hjkl through vim-herdr-navigation"
```

---

### Task 5: Document the herdr package and setup in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (add a herdr section; extend "Stow gotchas" with a herdr entry)

**Interfaces:**
- Consumes: the setup facts established in Tasks 1-4.
- Produces: reproducible per-device instructions.

- [ ] **Step 1: Add a herdr section**

Insert a new top-level section in `CLAUDE.md` (place it near the other tool
sections, e.g. after the "MCP servers (Playwright)" section):

```markdown
# herdr

herdr (homebrew-core `brew "herdr"`) is the primary agent workspace manager. The
`herdr/` Stow package ships a minimal `~/.config/herdr/config.toml` that remaps
herdr's keymap onto tmux muscle memory: prefix `ctrl+s`, `prefix s` = stacked
split, `prefix v` = side-by-side split, `settings` moved to `prefix ,`. `r`
(resize), `R` (reload), `b` (sidebar) stay at herdr defaults.

Direct `ctrl+h/j/k/l` pane navigation comes from the `vim-herdr-navigation`
herdr plugin (a vim-tmux-navigator port): it forwards the key into vim when a
vim/neovim pane is focused, else moves herdr focus, and falls back to tmux or
`wincmd` outside herdr. The nvim side is folded into the `vim-tmux-navigator`
spec in `nvim/.config/nvim/lua/plugins/nav.lua`.

`config.toml` is direct-stowed: herdr only writes the `onboarding` flag and never
rewrites keys at runtime (runtime state lives in separate files — `session.json`,
sockets, `*.log`). No base+generated pattern is needed (unlike codex).

Per-device setup (one time):

1. `brew bundle --file=Brewfile` — installs herdr.
2. `herdr plugin install paulbkim-dev/vim-herdr-navigation --yes` — registers the
   `vim-herdr-navigation.*` actions the config's `ctrl+hjkl` binds call. herdr
   plugins live in herdr's own store, not Stow-managed (like `tpm` for tmux).
3. `rm -f ~/.config/herdr/config.toml` (removes herdr's auto-created stub) then
   `stow -t ~ herdr`.
4. Launch nvim once so lazy.nvim syncs `vim-herdr-navigation`.
5. `herdr server reload-config` (or restart the server) to load the keys.
```

- [ ] **Step 2: Add a herdr entry to "Stow gotchas"**

Under the existing `# Stow gotchas` section, add a bullet:

```markdown
- **Before stowing `herdr`**: herdr auto-creates `~/.config/herdr/config.toml`
  (an `onboarding` stub) on first run. Remove it (`rm -f ~/.config/herdr/config.toml`)
  before `stow -t ~ herdr`, or Stow refuses to overlay the non-symlink target.
```

- [ ] **Step 3: Verify the edits landed**

Run:
```bash
grep -n '^# herdr$' CLAUDE.md
grep -n 'Before stowing .herdr' CLAUDE.md
```
Expected: both greps return a line.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(herdr): document herdr package and setup steps"
```

---

## Final verification (after all tasks — belongs to verification-before-completion)

Interactive checks that cannot run headless:

- Launch herdr. Press `prefix s` → new pane appears **below** (stacked). Press
  `prefix v` → new pane appears **to the right** (side-by-side). If reversed,
  swap `split_horizontal`/`split_vertical` in `config.toml` (one-line fix) and
  amend Task 1's commit.
- Press `prefix ,` → settings opens. Confirm `prefix s` no longer opens settings.
- In a herdr pane running nvim with two vertical splits: `ctrl+h`/`ctrl+l` move
  between vim splits, and at the edge fall through to the neighboring herdr pane.
  In a plain shell pane, `ctrl+h/j/k/l` move herdr pane focus.
- Confirm `readlink -f ~/.config/herdr/config.toml` still points into the repo
  (herdr did not replace the symlink with a regular file).

## Self-review notes

- **Spec coverage**: prefix (T1) · splits + settings relocation (T1) · r/R/b kept
  as defaults, i.e. absent from override (T1) · copy-mode/new-tab already match,
  no action needed (documented, no task) · pane nav plugin (T3) + nvim side (T4) ·
  f/a dropped for herdr-native, i.e. simply not bound (no task) · Brewfile (T2) ·
  Stow package + direct-stow (T1) · CLAUDE.md docs + setup steps (T5). The
  `ce-compound` solution doc (spec artifact 5) is a later workflow phase, not a
  plan task.
- **Placeholders**: none — every code/command step shows exact content.
- **Type/name consistency**: `vim-herdr-navigation.{left,down,up,right}` action
  names are identical across T1 (config), T3 (verify), and T4 (consumer). Repo
  path `paulbkim-dev/vim-herdr-navigation` identical in T2-dep, T3, T4, T5.
