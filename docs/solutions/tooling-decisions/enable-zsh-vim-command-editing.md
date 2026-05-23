---
title: "Enable zsh Vim command editing without losing insert-mode shortcuts"
date: 2026-05-23
category: tooling-decisions
module: zsh
problem_type: tooling_decision
component: tooling
severity: low
applies_when:
  - "Switching zsh command-line editing from Emacs mode to Vim mode"
  - "Preserving Ctrl-A, Ctrl-E, Ctrl-P, Ctrl-N, and arrow-key behavior while editing commands"
  - "Using tmux where copy mode is already configured for vi keys"
related_components:
  - development_workflow
tags:
  - zsh
  - vim-mode
  - bindkey
  - tmux
  - dotfiles
---

# Enable zsh Vim command editing without losing insert-mode shortcuts

## Context

The `zsh-vim-mode` branch changed zsh command-line editing from Emacs mode to Vim mode while keeping the insert-mode shortcuts that were already practical day to day.

tmux was intentionally left unchanged. Its config already had `set -g mode-keys vi` for copy mode and `set -g escape-time 10`, so the actual behavior gap lived in `zsh/.zshrc`.

Related `docs/solutions/` entries were process-only matches around dotfiles and worktree guards; none covered zsh keymaps, `bindkey -v`, `viins`, or `KEYTIMEOUT`.

## Guidance

When enabling zsh Vim command editing, use `bindkey -v`, then rebind practical insert-mode shortcuts on the `viins` keymap instead of relying on unscoped bindings.

Use a low `KEYTIMEOUT` so pressing Escape moves from insert mode to normal mode without a noticeable pause:

```zsh
bindkey -v
KEYTIMEOUT=1
```

Preserve expected shell-editing behavior explicitly in insert mode:

```zsh
bindkey -M viins "^a" beginning-of-line
bindkey -M viins "^e" end-of-line
bindkey -M viins "^p" history-search-backward
bindkey -M viins "^n" history-search-forward
bindkey -M viins "^[[A" history-search-backward
bindkey -M viins "^[[B" history-search-forward
bindkey -M viins "^[[C" forward-char
bindkey -M viins "^[[D" backward-char
```

Validate both syntax and runtime keymap state:

```sh
zsh -n zsh/.zshrc
```

Then load zsh interactively and inspect the keymap. The expected runtime signals are:

```sh
ZDOTDIR="$PWD/zsh" zsh -ic 'bindkey -lL main; print KEYTIMEOUT=$KEYTIMEOUT; bindkey -M viins "^A"; bindkey -M viins "^E"; bindkey -M viins "^P"; bindkey -M viins "^N"; bindkey -M viins "^[[A"; bindkey -M viins "^[[B"; bindkey -M viins "^[[C"; bindkey -M viins "^[[D"'
```

```text
bindkey -A viins main
KEYTIMEOUT=1
"^A" beginning-of-line
"^E" end-of-line
"^P" history-search-backward
"^N" history-search-forward
"^[[A" history-search-backward
"^[[B" history-search-forward
"^[[C" forward-char
"^[[D" backward-char
```

Do not use `zsh -fic` to validate startup-file behavior: `-f` disables startup files, so it can report default keymaps even when `.zshrc` is correct.

## Why This Matters

`bindkey -v` changes the active editing model, so bindings that worked in Emacs mode may not behave the same way unless they are attached to the right Vim keymap.

Binding the shortcuts to `viins` preserves familiar insert-mode ergonomics while still enabling normal-mode Vim editing. This avoids a common regression where Vim mode works technically, but everyday shell navigation becomes slower or surprising.

Leaving tmux untouched also keeps the blast radius small. Changing tmux just because zsh changed would mix two separate editing layers and risk breaking existing copy-mode behavior.

## When to Apply

- Switching zsh from Emacs command editing to Vim command editing.
- You want Vim normal mode in the shell without losing Ctrl-A, Ctrl-E, Ctrl-P, and Ctrl-N in insert mode.
- Arrow keys should continue to navigate history and move the cursor as before.
- tmux already has suitable vi copy-mode behavior and does not need related changes.

## Examples

Replace a global Emacs-mode binding block like this:

```zsh
bindkey -e
```

With a vi-mode block scoped to insert mode:

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

tmux check:

```sh
git diff -- tmux/.config/tmux/tmux.conf
```

Expected result: no output.

Interactive zsh validation can generate local cache files such as `zsh/.zcompdump` or `zsh/.zsh_plugins.zsh`. Do not commit those unless they are intentionally tracked artifacts.

## Related

- `docs/solutions/workflow-issues/enforce-codex-workflows-in-linked-worktrees-2026-05-20.md` — process-only relationship through linked-worktree guard behavior.
- `docs/solutions/workflow-issues/allow-codex-worktree-lifecycle-with-main-protection.md` — process-only relationship for worktree guard cleanup and approval behavior.
- `docs/solutions/tooling-decisions/configure-context-mode-for-codex-cli-2026-05-17.md` — weak dotfiles tooling relationship; no zsh keymap overlap.
