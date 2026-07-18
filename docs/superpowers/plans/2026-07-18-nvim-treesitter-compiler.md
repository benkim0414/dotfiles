# Nvim Treesitter Compiler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Neovim Treesitter parser installation work reproducibly on macOS/Homebrew and Linux, and avoid low-level parser build errors when no C compiler is available.

**Architecture:** Declare the compiler dependency in the repo's existing Homebrew package surface and document the Linux system-package equivalent. Add a small Neovim Treesitter install wrapper that checks for `cc`, `gcc`, or `clang` before calling `nvim-treesitter.install.install`, while leaving normal Treesitter parser/runtime behavior unchanged.

**Tech Stack:** Neovim 0.12.2, Lua, nvim-treesitter, Homebrew `Brewfile`, GNU Stow dotfiles.

## Global Constraints

- Resolve the failure for both macOS/Homebrew machines and Linux machines.
- Fresh dotfile installs should make the compiler dependency explicit.
- Neovim should avoid repeatedly surfacing low-level parser build errors when the dependency is missing.
- The Neovim preflight should accept any available compiler from this set: `cc`, `gcc`, or `clang`.
- If none is executable, Neovim should show one concise warning explaining that Treesitter parser installation requires a C compiler and skip both the startup parser install and FileType auto-install.
- Existing parser runtime behavior should otherwise remain unchanged.
- If a compiler is available but parser compilation fails for another reason, the existing Treesitter install error should still surface.
- In scope: `Brewfile`, Linux setup guidance in existing repository documentation, `syntax.lua` preflight, focused validation.
- Out of scope: a new Linux package manager automation system, replacing `nvim-treesitter`, changing the essential parser list, or installing system packages from inside Neovim.
- Brewfile CLI tools use `brew "<name>"` and stay sorted alphabetically.
- Commit each self-contained logical change separately, stage explicit paths only, and use conventional commit subjects.

---

## File Structure

- Modify `Brewfile`: add Homebrew `gcc` in sorted CLI tool order so Homebrew-managed machines have a compiler package available.
- Modify `CLAUDE.md`: document the Treesitter parser compiler requirement and the platform-specific setup commands for macOS/Homebrew, Fedora, and Debian/Ubuntu.
- Modify `nvim/.config/nvim/lua/plugins/syntax.lua`: add a local compiler preflight and route startup/FileType parser installs through it.

---

### Task 1: Document and Declare the Compiler Dependency

**Files:**
- Modify: `Brewfile`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Existing repo package conventions in `CLAUDE.md` and sorted `Brewfile` CLI list.
- Produces: Homebrew package entry `brew "gcc"` and setup documentation consumed by users before running Neovim Treesitter parser installs.

- [ ] **Step 1: Add the Homebrew compiler package**

Edit `Brewfile` so the CLI section includes `brew "gcc"` in alphabetical order between `brew "fzf"` and `brew "gh"`:

```ruby
brew "antidote"
brew "bash"
brew "bat"
brew "bitwarden-cli"
brew "coreutils"
brew "eza"
brew "fd"
brew "fzf"
brew "gcc"
brew "gh"
brew "git-delta"
brew "git"
brew "herdr"
brew "keychain"
brew "lazygit"
brew "luarocks"
brew "mise"
brew "neovim"
brew "ripgrep"
brew "shfmt"
brew "starship"
brew "stow"
brew "tmux"
brew "uv"
brew "wget"
brew "zoxide"
brew "zsh"
cask "bitwarden"
cask "claude"
cask "codex"
cask "docker-desktop"
cask "ghostty"
cask "google-chrome"
cask "raycast"
```

- [ ] **Step 2: Add cross-platform Neovim setup guidance**

In `CLAUDE.md`, after the "Adding a new tool" section and before `# Secrets`, add this section:

```markdown
# Neovim Treesitter parser compilation

`nvim-treesitter` compiles parsers with a C compiler. Make sure one of `cc`,
`gcc`, or `clang` is available on `PATH` before the first Neovim startup that
installs parsers.

- macOS/Homebrew: `brew bundle --file=Brewfile` installs Homebrew `gcc`; Apple's
  Command Line Tools also provide `cc` when installed.
- Fedora: `sudo dnf install gcc`
- Debian/Ubuntu: `sudo apt install build-essential`

After installing compiler tools, run `nvim --headless "+TSInstallSync json" +qa`
to verify the JSON parser compiles.
```

- [ ] **Step 3: Verify the package and docs edit**

Run:

```bash
rg -n 'brew "gcc"|Treesitter parser compilation|sudo dnf install gcc|sudo apt install build-essential' Brewfile CLAUDE.md
```

Expected output includes one `Brewfile` line and three `CLAUDE.md` lines matching
these patterns:

```text
Brewfile:9:brew "gcc"
CLAUDE.md:[0-9]+:# Neovim Treesitter parser compilation
CLAUDE.md:[0-9]+:- Fedora: `sudo dnf install gcc`
CLAUDE.md:[0-9]+:- Debian/Ubuntu: `sudo apt install build-essential`
```

- [ ] **Step 4: Inspect the diff**

Run:

```bash
git diff -- Brewfile CLAUDE.md
```

Expected: only `brew "gcc"` is added to `Brewfile`, and only the Neovim Treesitter parser compilation setup section is added to `CLAUDE.md`.

- [ ] **Step 5: Commit the dependency declaration**

Run:

```bash
git add Brewfile CLAUDE.md
git diff --cached
git commit -m "docs: document nvim treesitter compiler setup"
```

Expected: commit succeeds. If the commit hook rejects the subject because the scope is missing or invalid, inspect `git log --format=%s -50` and retry with the nearest accepted conventional subject.

---

### Task 2: Add Treesitter Compiler Preflight

**Files:**
- Modify: `nvim/.config/nvim/lua/plugins/syntax.lua`

**Interfaces:**
- Consumes: Compiler guidance from Task 1 and existing `nvim-treesitter.install.install({ lang })` API.
- Produces: Local functions `has_treesitter_compiler()`, `notify_missing_treesitter_compiler()`, and `install_treesitter_parsers(langs)` inside the plugin `config` function.

- [ ] **Step 1: Add local compiler preflight functions**

In `nvim/.config/nvim/lua/plugins/syntax.lua`, immediately after:

```lua
      local ts_install = require('nvim-treesitter.install')
```

insert:

```lua
      local missing_compiler_warned = false

      local function has_treesitter_compiler()
        return vim.fn.executable("cc") == 1
          or vim.fn.executable("gcc") == 1
          or vim.fn.executable("clang") == 1
      end

      local function notify_missing_treesitter_compiler()
        if missing_compiler_warned then
          return
        end

        missing_compiler_warned = true
        vim.schedule(function()
          vim.notify(
            "Treesitter parser installation requires a C compiler (cc, gcc, or clang). Install compiler tools, then run :TSUpdate.",
            vim.log.levels.WARN
          )
        end)
      end

      local function install_treesitter_parsers(langs)
        if has_treesitter_compiler() then
          ts_install.install(langs)
        else
          notify_missing_treesitter_compiler()
        end
      end
```

- [ ] **Step 2: Route startup parser installs through the preflight**

Replace:

```lua
      -- Install essential parsers on startup (async, skips already-installed)
      ts_install.install({ 'lua', 'go', 'python', 'json', 'markdown' })
```

with:

```lua
      -- Install essential parsers on startup (async, skips already-installed)
      install_treesitter_parsers({ 'lua', 'go', 'python', 'json', 'markdown' })
```

- [ ] **Step 3: Route FileType auto-installs through the preflight**

Inside the `FileType` autocmd callback, replace:

```lua
            ts_install.install({ lang })
```

with:

```lua
            install_treesitter_parsers({ lang })
```

The full beginning of `config = function()` should now read:

```lua
    config = function()
      local ts_install = require('nvim-treesitter.install')
      local missing_compiler_warned = false

      local function has_treesitter_compiler()
        return vim.fn.executable("cc") == 1
          or vim.fn.executable("gcc") == 1
          or vim.fn.executable("clang") == 1
      end

      local function notify_missing_treesitter_compiler()
        if missing_compiler_warned then
          return
        end

        missing_compiler_warned = true
        vim.schedule(function()
          vim.notify(
            "Treesitter parser installation requires a C compiler (cc, gcc, or clang). Install compiler tools, then run :TSUpdate.",
            vim.log.levels.WARN
          )
        end)
      end

      local function install_treesitter_parsers(langs)
        if has_treesitter_compiler() then
          ts_install.install(langs)
        else
          notify_missing_treesitter_compiler()
        end
      end

      -- Install essential parsers on startup (async, skips already-installed)
      install_treesitter_parsers({ 'lua', 'go', 'python', 'json', 'markdown' })

      -- Auto-install parsers when opening a new filetype
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TSAutoInstall", { clear = true }),
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(ev.match) or ev.match
          if not pcall(vim.treesitter.get_parser, ev.buf, lang) then
            install_treesitter_parsers({ lang })
          end
        end,
      })
```

- [ ] **Step 4: Verify Lua syntax by loading Neovim headlessly**

Run:

```bash
nvim --headless '+lua vim.wait(100)' +qa
```

Expected: command exits `0`. On a machine without `cc`, `gcc`, or `clang`, warning output may mention the missing Treesitter compiler, but the command must not include `tree-sitter build`, `Failed to compile parser`, or `Failed to execute the C compiler`.

- [ ] **Step 5: Verify the missing-compiler branch explicitly**

Run:

```bash
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" nvim --headless '+lua vim.wait(100)' +qa 2>&1 | tee /tmp/nvim-treesitter-no-compiler.log
```

Then run:

```bash
rg -n 'Treesitter parser installation requires a C compiler|tree-sitter build|Failed to compile parser|Failed to execute the C compiler' /tmp/nvim-treesitter-no-compiler.log
```

Expected: the log may contain the concise warning `Treesitter parser installation requires a C compiler`, and must not contain `tree-sitter build`, `Failed to compile parser`, or `Failed to execute the C compiler`.

- [ ] **Step 6: Verify compiler-present behavior when a compiler is available**

Run:

```bash
command -v cc || command -v gcc || command -v clang
```

Expected when compiler tools are installed: output is a compiler path. If this command exits non-zero because the current machine does not have compiler tools installed yet, record `compiler-present validation skipped: no compiler on PATH` in the task report and continue.

If the compiler command found a path, run:

```bash
nvim --headless '+TSInstallSync json' +qa
```

Expected: command exits `0`, and the JSON parser compiles or is already installed.

- [ ] **Step 7: Inspect the diff**

Run:

```bash
git diff -- nvim/.config/nvim/lua/plugins/syntax.lua
```

Expected: only the local compiler preflight helpers are added and the two parser install calls are routed through `install_treesitter_parsers`.

- [ ] **Step 8: Commit the Neovim preflight**

Run:

```bash
git add nvim/.config/nvim/lua/plugins/syntax.lua
git diff --cached
git commit -m "fix: guard nvim treesitter parser installs"
```

Expected: commit succeeds. If the commit hook rejects the subject because the scope is missing or invalid, inspect `git log --format=%s -50` and retry with the nearest accepted conventional subject.

---

## Final Verification

- [ ] Run:

```bash
git status --short --branch
```

Expected: branch is `fix/nvim-treesitter-compiler` and the worktree is clean except for ignored `.superpowers/` scratch files.

- [ ] Run:

```bash
git log --oneline --max-count=4
```

Expected: latest commits include the implementation commits from Task 1 and Task 2, plus the design/plan commits if they were made in this branch.
