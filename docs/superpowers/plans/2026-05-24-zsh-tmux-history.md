# Zsh Tmux History Implementation Plan

## Feature

Make zsh command history persist and refresh reliably in new tmux sessions and
panes.

## Spec

`docs/superpowers/specs/2026-05-24-zsh-tmux-history-design.md`

## Current State

`zsh/.zshrc` currently sets `HISTFILE`, `HISTSIZE`, `SAVEHIST`,
`INC_APPEND_HISTORY`, and `SHARE_HISTORY`. It does not explicitly create the
history directory, and it does not force interactive shells to import newly
appended history before each prompt.

## Task 1: Harden zsh History Initialization

Files:

- `zsh/.zshrc`

Steps:

1. Near the existing `HISTFILE` assignment, create the parent directory with
   `mkdir -p "${HISTFILE:h}"`.
2. Keep `HISTFILE`, `HISTSIZE`, and `SAVEHIST` at their current values.
3. Keep the existing history options that control timestamped history, duplicate
   handling, space-prefixed commands, blank reduction, verification, immediate
   append, and shared history.
4. Add a small `precmd` hook after the history options that runs `fc -RI` so
   each prompt imports history appended by other shells.
5. Avoid changing aliases, completion, prompt setup, tmux config, or unrelated
   keybindings.

Verification:

- Run `zsh -n zsh/.zshrc`.
- Run an isolated zsh command that loads the edited `.zshrc`, sets
  `XDG_STATE_HOME` to a temporary directory, and verifies that the
  `zsh/history` parent directory is created.
- Inspect the resulting diff to confirm only the intended history setup changed.

## Task 2: Review and Document the Result

Files:

- `docs/solutions/` if the fix exposes a reusable lesson worth documenting.

Steps:

1. Review the implementation against the spec.
2. Run final verification commands.
3. Capture the reusable lesson with `ce-compound` if the result teaches a
   durable zsh/tmux history pattern.
4. Finish the branch through the approved branch-completion workflow.

Verification:

- Code review finds no critical or important issues.
- Final branch status is clean except for intentional committed changes.
