# Zsh Vim Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Vim-style zsh command editing while keeping the existing practical command-line shortcuts.

**Architecture:** This is a single-file shell configuration change. `zsh/.zshrc` owns zsh line-editor setup, so the plan changes only that keybinding block and leaves tmux untouched because tmux already has vi copy mode and a low escape timeout.

**Tech Stack:** zsh ZLE keymaps, tmux config already present, git.

---

## File Structure

- Modify: `zsh/.zshrc:39-47`
  - Responsibility: Configure zsh command-line editing mode and keybindings.
- Do not modify: `tmux/.config/tmux/tmux.conf`
  - Reason: Existing `mode-keys vi` and `escape-time 10` already support the requested behavior.

### Task 1: Enable zsh vi command editing

**Files:**
- Modify: `zsh/.zshrc:39-47`

- [ ] **Step 1: Inspect the current zsh keybinding block**

Run:

```bash
nl -ba zsh/.zshrc | sed -n '34,52p'
```

Expected: Lines show `bindkey -e` followed by the existing `Ctrl-A`, `Ctrl-E`, `Ctrl-P`, `Ctrl-N`, and arrow-key bindings.

- [ ] **Step 2: Replace the keybinding block**

Change this block:

```zsh
bindkey -e
bindkey "^a" beginning-of-line
bindkey "^e" end-of-line
bindkey "^p" history-search-backward
bindkey "^n" history-search-forward
bindkey "^[[A" history-search-backward
bindkey "^[[B" history-search-forward
bindkey "^[[C" forward-char
bindkey "^[[D" backward-char
```

To this block:

```zsh
bindkey -v
KEYTIMEOUT=1

bindkey -M viins "^a" beginning-of-line
bindkey -M viins "^e" end-of-line
bindkey -M viins "^p" history-search-backward
bindkey -M viins "^n" history-search-forward
bindkey -M viins "^[[A" history-search-backward
bindkey -M viins "^[[B" history-search-forward
bindkey -M viins "^[[C" forward-char
bindkey -M viins "^[[D" backward-char
```

Rationale: `bindkey -v` enables zsh vi editing. `KEYTIMEOUT=1` makes `Esc` responsive in tmux and normal terminals. Binding the convenience keys specifically in `viins` keeps them available while typing commands without changing normal-mode Vim behavior.

- [ ] **Step 3: Run zsh syntax validation**

Run:

```bash
zsh -n zsh/.zshrc
```

Expected: No output and exit code `0`.

- [ ] **Step 4: Verify the loaded keymap configuration**

Run:

```bash
ZDOTDIR="$PWD/zsh" zsh -fic 'bindkey -lL main; print KEYTIMEOUT=$KEYTIMEOUT; bindkey -M viins "^A"; bindkey -M viins "^E"; bindkey -M viins "^P"; bindkey -M viins "^N"'
```

Expected output includes:

```text
bindkey -A viins main
KEYTIMEOUT=1
"^A" beginning-of-line
"^E" end-of-line
"^P" history-search-backward
"^N" history-search-forward
```

- [ ] **Step 5: Verify tmux remains unchanged**

Run:

```bash
git diff -- tmux/.config/tmux/tmux.conf
```

Expected: No output.

- [ ] **Step 6: Review the implementation diff**

Run:

```bash
git diff -- zsh/.zshrc
```

Expected diff:

```diff
-bindkey -e
-bindkey "^a" beginning-of-line
-bindkey "^e" end-of-line
-bindkey "^p" history-search-backward
-bindkey "^n" history-search-forward
-bindkey "^[[A" history-search-backward
-bindkey "^[[B" history-search-forward
-bindkey "^[[C" forward-char
-bindkey "^[[D" backward-char
+bindkey -v
+KEYTIMEOUT=1
+
+bindkey -M viins "^a" beginning-of-line
+bindkey -M viins "^e" end-of-line
+bindkey -M viins "^p" history-search-backward
+bindkey -M viins "^n" history-search-forward
+bindkey -M viins "^[[A" history-search-backward
+bindkey -M viins "^[[B" history-search-forward
+bindkey -M viins "^[[C" forward-char
+bindkey -M viins "^[[D" backward-char
```

- [ ] **Step 7: Commit the zsh config change**

Run:

```bash
git add zsh/.zshrc
git commit -m "feat(zsh): enable vim command editing"
```

Expected: A commit is created on branch `zsh-vim-mode`.
