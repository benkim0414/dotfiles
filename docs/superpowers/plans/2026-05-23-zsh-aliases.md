# Zsh Aliases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move zsh aliases into `zsh/.zsh_aliases`, remove stale Claude aliases, and add a guarded `k="kubectl"` shortcut.

**Architecture:** Keep `.zshrc` responsible for shell startup, plugins, environment loading, completions, and helper functions. Add `zsh/.zsh_aliases` as an alias-only file sourced by `.zshrc` after per-machine environment loading and before helper functions. Register kubectl completion only when `kubectl` is available and zsh completion is initialized.

**Tech Stack:** zsh dotfiles, shell aliases, zsh completion, git worktree branch `zsh-aliases`.

---

### Task 1: Extract Alias Declarations

**Files:**
- Create: `zsh/.zsh_aliases`
- Modify: `zsh/.zshrc`

- [ ] **Step 1: Create the alias-only file**

Create `zsh/.zsh_aliases` with grouped aliases:

```zsh
# Editor
alias vi="nvim"
alias vim="nvim"

# Listing
alias ld="eza -lD"
alias lf="eza -lf --color=always | grep -v /"
alias lh="eza -dl .* --group-directories-first"
alias ls="eza -a --color=always --group-directories-first"
alias lt="eza -al --sort=modified"

# Git
alias lg="lazygit"

# Claude Code
alias cc="claude"
alias ccc="claude --continue"
alias ccr="claude --resume"
alias ccp="claude --print"

# Kubernetes
alias k="kubectl"
```

- [ ] **Step 2: Replace inline aliases in `.zshrc` with a source guard**

In `zsh/.zshrc`, remove the inline alias block currently after the per-machine env line. Replace it with:

```zsh
# Aliases
[ -r ~/.zsh_aliases ] && source ~/.zsh_aliases
```

Leave these helper functions in `.zshrc`:

```zsh
sz() { source ~/.zshrc }

bwu() { export BW_SESSION="$(bw unlock --raw)" }
```

- [ ] **Step 3: Verify syntax**

Run:

```bash
zsh -n zsh/.zshrc zsh/.zsh_aliases
```

Expected: command exits `0` with no output.

- [ ] **Step 4: Commit alias extraction**

Run:

```bash
git add zsh/.zshrc zsh/.zsh_aliases
git commit -m "feat(zsh): extract aliases"
```

Expected: commit includes only `zsh/.zshrc` and `zsh/.zsh_aliases`.

### Task 2: Add Guarded Kubectl Completion Validation

**Files:**
- Modify: `zsh/.zshrc`
- Modify: `zsh/.zsh_aliases` if alias placement needs adjustment

- [ ] **Step 1: Inspect current completion ordering**

Confirm `zsh/.zshrc` initializes zsh completion before sourcing aliases. The current file should still contain:

```zsh
autoload -Uz compinit
compinit -C
```

Expected: the alias source block appears after completion setup.

- [ ] **Step 2: Add guarded kubectl completion for the `k` alias**

After sourcing aliases in `zsh/.zshrc`, add this guarded completion block:

```zsh
if (( $+commands[kubectl] )); then
  source <(kubectl completion zsh)
  compdef __start_kubectl k
fi
```

This keeps startup quiet when `kubectl` is missing and gives `k` the same completion function as `kubectl` when available.

- [ ] **Step 3: Verify syntax again**

Run:

```bash
zsh -n zsh/.zshrc zsh/.zsh_aliases
```

Expected: command exits `0` with no output.

- [ ] **Step 4: Verify aliases in a clean zsh process**

Run:

```bash
ZDOTDIR="$PWD/zsh" zsh -ic 'alias k; alias cc; alias ccc; alias ccr; alias ccp; alias vim; alias ls; alias lg; ! alias cca >/dev/null 2>&1; ! alias ccw >/dev/null 2>&1'
```

Expected: command exits `0`, prints the kept aliases, and does not print `cca` or `ccw`.

- [ ] **Step 5: Verify kubectl completion behavior when possible**

If `kubectl` is installed, run:

```bash
ZDOTDIR="$PWD/zsh" zsh -ic '(( $+functions[__start_kubectl] )) && whence -w _kubectl >/dev/null && echo kubectl-completion-ok'
```

Expected when `kubectl` is installed: prints `kubectl-completion-ok` and exits `0`.

If `kubectl` is not installed, run:

```bash
ZDOTDIR="$PWD/zsh" zsh -ic 'alias k'
```

Expected when `kubectl` is not installed: prints `k=kubectl` and exits `0`; startup should not error.

- [ ] **Step 6: Commit kubectl completion validation changes**

If Task 2 changed files after Task 1, run:

```bash
git add zsh/.zshrc zsh/.zsh_aliases
git commit -m "feat(zsh): add kubectl alias completion"
```

Expected: commit contains the guarded kubectl completion wiring. If Task 1 already included the completion block and no files changed, skip this commit.

### Task 3: Final Verification

**Files:**
- Verify: `zsh/.zshrc`
- Verify: `zsh/.zsh_aliases`

- [ ] **Step 1: Review final diff**

Run:

```bash
git diff main...HEAD -- zsh/.zshrc zsh/.zsh_aliases docs/superpowers/specs/2026-05-23-zsh-aliases-design.md docs/superpowers/plans/2026-05-23-zsh-aliases.md
```

Expected: diff shows the approved design doc, this plan, alias extraction, removal of `cca` and `ccw`, addition of `k`, and guarded kubectl completion only.

- [ ] **Step 2: Run final status check**

Run:

```bash
git status --short
```

Expected: no unstaged or staged tracked changes remain. Untracked shell-generated files such as `zsh/.zcompdump` and `zsh/.zsh_plugins.zsh` may exist and should not be added unless explicitly requested.
