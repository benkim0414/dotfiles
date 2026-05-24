# Zsh Tmux History Design

## Problem

New tmux sessions and panes do not reliably show historical zsh commands through
Up/Ctrl-P or Ctrl-R. Commands entered inside tmux also do not reliably persist
for later shells.

The existing zsh configuration already sets a shared history file and enables
`INC_APPEND_HISTORY` and `SHARE_HISTORY`, so the fix should strengthen zsh's
history lifecycle rather than introduce tmux-specific history behavior.

## Goals

- Keep one shared zsh command history across normal terminals and tmux.
- Make new interactive shells load existing history immediately.
- Make commands entered in one shell available to other shells quickly.
- Preserve the existing history location:
  `${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history`.
- Keep the change small and local to zsh history setup.

## Non-Goals

- Do not create separate tmux-only history files.
- Do not change tmux's default shell unless verification shows tmux is not
  launching zsh.
- Do not alter unrelated keybindings, prompt setup, aliases, or plugin loading.

## Approach

Update `zsh/.zshrc` near the current history settings:

1. Ensure the history directory exists before zsh tries to read or write
   `HISTFILE`.
2. Keep the existing history size and file path.
3. Use zsh history options that append commands immediately and share history
   between interactive shells.
4. Add a small `precmd` hook that imports appended history before each prompt.

The `precmd` hook should use zsh's `fc -RI` builtin command so it stays
dependency-free.
The intended behavior is that a fresh tmux pane starts with the existing
history file loaded, and active panes refresh their in-memory history as other
shells append commands.

## Error Handling

If the history directory cannot be created, zsh startup should continue and
zsh's normal history warnings or behavior should apply. The configuration
should not exit the shell or make tmux unusable because history persistence
failed.

## Testing

Verification should cover:

- Zsh parses the updated `.zshrc`.
- A temporary zsh invocation using an isolated `ZDOTDIR` can create and use the
  configured history directory.
- Manual tmux verification after stowing/reloading dotfiles:
  - Run a command in one zsh shell.
  - Open a new tmux pane or session.
  - Confirm Up/Ctrl-P and Ctrl-R can find the command.
  - Close and reopen tmux, then confirm the command is still available.
