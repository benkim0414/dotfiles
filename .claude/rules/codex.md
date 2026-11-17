---
paths:
  - "codex/**"
---

# Codex

- Run `mkdir -p ~/.codex` before `stow -t ~ codex`. Otherwise Stow
  tree-folds `~/.codex` into a directory symlink, and Codex writes its
  runtime state (history, logs, sessions) into the repo.
- `codex/.codex/config.base.toml` is a reference template. Manage the active
  `~/.codex/config.toml` by hand; no command syncs them. Codex writes UI
  notices, plugin state and project trust entries into `config.toml`, so git
  ignores it. When you apply template settings, keep its device-local entries.
