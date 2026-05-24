---
title: "Use explicit zsh history refresh for tmux sessions"
date: 2026-05-24
category: tooling-decisions
module: zsh
problem_type: tooling_decision
component: tooling
severity: low
applies_when:
  - "New tmux panes or sessions do not show older zsh commands through Up, Ctrl-P, or Ctrl-R"
  - "Commands entered in one interactive zsh shell should appear quickly in another"
  - "A dotfiles repo uses one shared HISTFILE across normal terminals and tmux"
related_components:
  - tmux
  - development_workflow
tags:
  - zsh
  - tmux
  - history
  - dotfiles
---

# Use explicit zsh history refresh for tmux sessions

## Context

New tmux sessions can feel like they have no history when zsh has not loaded
the shared history file or has not imported commands appended by other shells.
This affects Up/Ctrl-P history navigation and Ctrl-R reverse search because
both read from zsh's in-memory history list.

## Guidance

Use one shared history file and one explicit sharing model:

- Keep `HISTFILE` pointed at the shared XDG state location.
- Create the history file's parent directory before zsh tries to write history.
- Keep `INC_APPEND_HISTORY` enabled so commands are written as they are entered.
- Turn `SHARE_HISTORY` off when manually importing with `fc -RI`.
- Add a `precmd` hook that imports appended history before each prompt.

`SHARE_HISTORY` is not just an import toggle. zsh documents it as both importing
new commands and appending typed commands, overlapping with
`INC_APPEND_HISTORY`. When prompt-time imports are needed, zsh recommends the
explicit model: `INC_APPEND_HISTORY` on, `SHARE_HISTORY` off, and manual
`fc -RI` imports.

## Why This Matters

Combining `SHARE_HISTORY`, `INC_APPEND_HISTORY`, and a manual `fc -RI` hook
creates overlapping history refresh paths. That makes the behavior harder to
reason about and can obscure whether tmux is the problem. The explicit model
keeps persistence and refresh timing separate:

- append timing is handled by `INC_APPEND_HISTORY`;
- import timing is handled by the prompt hook;
- tmux remains a normal zsh host rather than a special case.

## When to Apply

Apply this pattern when the goal is shared interactive zsh history across tmux
and non-tmux shells. Do not apply it when a user wants isolated per-session or
per-tmux history files.

## Related

- `docs/solutions/tooling-decisions/enable-zsh-vim-command-editing.md` -- same
  zsh/tmux user experience area, but focused on command-line editing keys
  rather than history persistence.
