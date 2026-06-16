---
title: "fc -RI on the zsh precmd hook breaks Ctrl+P/Ctrl+N history navigation"
date: 2026-06-16
category: developer-experience
module: zsh
problem_type: integration_issue
component: shell-config
severity: medium
applies_when:
  - "zsh registers a precmd hook that runs fc -R / fc -RI to re-import history each prompt"
  - "SHARE_HISTORY is unset and history sync is done manually"
  - "Ctrl+P/Ctrl+N or up/down arrows recall nothing on an empty prompt"
symptoms:
  - "Pressing Ctrl+P on a fresh prompt leaves the buffer empty"
  - "$HISTNO is empty in the line editor despite ${#history} being populated"
  - "fc -l shows full history but ZLE navigation widgets do nothing"
root_cause: fc_r_resets_zle_history_position_each_precmd
resolution_type: replace_manual_import_with_share_history
related_components:
  - zsh
  - zle
  - zsh-autosuggestions
tags:
  - zsh
  - history
  - zle
  - keybindings
  - share-history
  - pty-debugging
---

# fc -RI on the zsh precmd hook breaks Ctrl+P/Ctrl+N history navigation

## Problem

Ctrl+P / Ctrl+N and the up/down arrows recalled no history in interactive
zsh. On an empty prompt the keys did nothing — the line buffer stayed empty.

The keybindings looked correct (`bindkey -M viins "^p"
history-beginning-search-backward`), the history file had ~180 entries, and
`${#history}` confirmed the entries were loaded into the shell. Yet ZLE
navigation produced an empty buffer and `$HISTNO` was empty.

## Root cause

A `precmd` hook re-imported the history file on every prompt:

```zsh
unsetopt SHARE_HISTORY
autoload -Uz add-zsh-hook
_import_appended_history() {
  [[ -r "$HISTFILE" ]] && fc -RI
}
add-zsh-hook precmd _import_appended_history
```

`fc -R` (read history file) run from `precmd` resets ZLE's history position
each time the prompt is drawn. `$HISTNO` is left empty, so the history
navigation widgets have no anchor to walk backward from and silently do
nothing. The widget choice was irrelevant — `up-line-or-history`,
`history-search-backward`, and `history-beginning-search-backward` all
failed identically. Wrapping by zsh-autosuggestions was also a red herring.

The hook existed (with `unsetopt SHARE_HISTORY`) to sync history across
concurrent shells with "predictable refresh timing." But `INC_APPEND_HISTORY`
already writes each command immediately, so new shells always start with full
history. The hook's only added value — letting already-running shells pick up
commands from other live shells — is exactly what `SHARE_HISTORY` does
natively, without resetting the ZLE position.

## Resolution

Drop the manual import hook and enable `SHARE_HISTORY`:

```zsh
setopt SHARE_HISTORY             # Share history across concurrent sessions in real time
```

Tradeoff: `SHARE_HISTORY` interleaves other concurrent shells' commands into
the current session's history in real time. Accepted here in exchange for
working navigation and zero custom hook code.

## How it was diagnosed

A static config review and a fresh `zsh -i` fed from a pipe both looked
healthy (bindings correct, history loaded) because a pipe never invokes ZLE.
The bug only reproduces with a real line editor. The decisive technique was
driving a pseudo-terminal (Python `pty.fork`) running `zsh -i`, sending a
literal Ctrl+P byte (`\x10`), then triggering a custom ZLE widget bound to a
spare key that wrote `$BUFFER` and `$HISTNO` to a file. Bisecting with the
precmd hook removed flipped the buffer from empty to the recalled command —
isolating the hook as the sole cause.

Lesson: to test zsh ZLE behavior you must use a pty; piped stdin bypasses the
line editor and hides editor-only bugs.
