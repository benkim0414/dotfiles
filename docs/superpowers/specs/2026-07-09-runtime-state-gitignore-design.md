# Runtime State Gitignore Design

## Problem

Local tool state is surfacing as untracked repository content:

- `codex/.codex/context-mode/sessions/*` contains context-mode session
  databases and per-process stats files.
- `codex/.codex/goals_1.sqlite*` and `codex/.codex/memories_1.sqlite*` are
  runtime SQLite databases with WAL and SHM sidecar files.
- `bin/.local/bin/herdr` is a Herdr installer-managed platform binary.

The current `.gitignore` already has a Codex runtime-artifacts section, but its
SQLite patterns cover only `state*.sqlite*` and `logs*.sqlite*`. It also tracks
first-party helper scripts under `bin/.local/bin`, so ignoring that whole
directory would hide future repo-managed scripts.

Herdr's installer and manual install documentation place a platform-specific
binary at `~/.local/bin/herdr`. Because Herdr publishes separate Linux and
macOS binaries, committing the installed Linux binary would make the dotfiles
less portable.

## Design

Update `.gitignore` with narrow, explicit runtime/install rules:

- Add `bin/.local/bin/herdr` under a local installer-managed binaries section.
- Add `codex/.codex/context-mode/sessions/` to the Codex runtime section.
- Add `codex/.codex/goals_*.sqlite*` and
  `codex/.codex/memories_*.sqlite*` to cover runtime databases and SQLite
  sidecars.

Do not ignore all of `bin/.local/bin/`. Existing tracked files there are
repo-managed helper scripts, and new helper scripts should remain visible in
`git status` by default.

Do not touch the unrelated modified Neovim lockfile.

## Verification

- Run `git check-ignore -v` for the observed Herdr binary, context-mode session
  database, context-mode stats JSON, goals SQLite files, and memories SQLite
  files.
- Run `git status --short --untracked-files=all` in the primary checkout and
  confirm the runtime/install artifacts no longer appear, while unrelated
  tracked changes such as `nvim/.config/nvim/lazy-lock.json` remain visible.
