# zsh Ctrl+P/Ctrl+N history navigation fix

## Problem

In interactive zsh, Ctrl+P / Ctrl+N (and the up/down arrows) recall no
history. Pressing them on an empty prompt does nothing — the buffer stays
empty.

## Root cause

`zsh/.zshrc` registers `_import_appended_history` on the `precmd` hook,
which runs `fc -RI` before every prompt to re-import the history file. That
`fc -R` call resets ZLE's history position on each prompt: `HISTNO` is left
empty and the history-navigation widgets have no anchor to walk backward
from. Result: Ctrl+P/Ctrl+N and arrow history do nothing.

Verified empirically via pty: with the precmd hook removed, Ctrl+P recalls
the previous command and `HISTNO` is populated. Bindings, the history file
(215 lines on disk, ~180 loaded), and widget wrapping by zsh-autosuggestions
were all confirmed correct — the hook was the sole cause.

The hook was added (with `unsetopt SHARE_HISTORY`) to get cross-shell history
sync with "predictable refresh timing." But `INC_APPEND_HISTORY` already
writes each command to the file immediately, so new shells always start with
full history. The hook's only added value was letting already-running shells
pick up commands typed in other live shells — which is exactly what
`SHARE_HISTORY` provides natively, without breaking navigation.

## Fix (approved: real-time sharing)

In `zsh/.zshrc`:

1. Replace `unsetopt SHARE_HISTORY` with `setopt SHARE_HISTORY` and update
   the comment to describe real-time cross-session sharing.
2. Delete the `autoload -Uz add-zsh-hook` + `_import_appended_history`
   function + `add-zsh-hook` registration block (no longer needed; nothing
   else uses `add-zsh-hook`).

`SHARE_HISTORY` implies incremental append/import, so cross-shell sync is
preserved. Tradeoff accepted by user: concurrent shells' commands interleave
into the session history in real time.

## Verification

Drive a real pty against the edited config: send Ctrl+P on a fresh prompt and
confirm the buffer fills with the previous command and `HISTNO` is non-empty.
