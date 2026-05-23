# Zsh Vim Mode Design

## Goal

Enable Vim-style command editing in zsh while preserving the practical readline-style shortcuts already used in this dotfiles repo. The setup should work comfortably inside tmux without changing tmux behavior unless validation shows it is necessary.

## Current State

- `zsh/.zshrc` currently sets Emacs command editing with `bindkey -e`.
- The same file binds convenience keys such as `Ctrl-A`, `Ctrl-E`, `Ctrl-P`, `Ctrl-N`, and arrow-key history search.
- `tmux/.config/tmux/tmux.conf` already enables vi copy mode with `set -g mode-keys vi`.
- tmux already uses `set -g escape-time 10`, which should keep `Esc` responsive for zsh vi mode inside tmux.

## Recommended Approach

Use zsh vi mode as the shell editing baseline and reapply the existing practical shortcuts where they remain useful. This keeps the behavioral change focused: normal command editing becomes modal, but common shortcuts and arrow behavior still work during insert-mode editing.

The design intentionally avoids adding a prompt mode indicator. The prompt is managed by Starship, so a mode indicator would add widget hooks or a Starship custom module for a benefit that is not required for the initial setup.

## Configuration Changes

Update `zsh/.zshrc` to:

- Replace `bindkey -e` with `bindkey -v`.
- Set a low `KEYTIMEOUT` so `Esc` switches modes quickly.
- Preserve existing convenience bindings in insert mode:
  - `Ctrl-A` moves to beginning of line.
  - `Ctrl-E` moves to end of line.
  - `Ctrl-P` and Up search history backward.
  - `Ctrl-N` and Down search history forward.
  - Left and Right move by one character.
- Add normal-mode bindings only where they support expected Vim command editing without surprising behavior.

Leave `tmux/.config/tmux/tmux.conf` unchanged unless manual validation shows escape handling is slow or conflicting.

## Validation

Run noninteractive checks after editing:

- `zsh -n zsh/.zshrc` to confirm the file parses.
- A zsh keymap inspection command, if practical, to verify vi mode loads without errors.

Manual validation after reloading zsh:

- Type a command, press `Esc`, and use Vim movement such as `h`, `l`, `b`, `w`, `0`, `$`.
- Press `i`, `a`, or `A` to return to insert editing.
- Confirm `Ctrl-A`, `Ctrl-E`, `Ctrl-P`, `Ctrl-N`, and arrow history search still work while editing commands.
- Confirm tmux copy mode still uses vi bindings.

## Out Of Scope

- Prompt mode indicator.
- New zsh plugins.
- Changes to tmux prefix, pane navigation, or copy-mode bindings.
- Reworking unrelated shell aliases or plugin loading.
