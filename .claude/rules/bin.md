---
paths:
  - "bin/**"
---

# bin

- Custom scripts go in `bin/.local/bin/` and must be executable.
- Run `mkdir -p ~/.local/bin` before `stow -t ~ bin`. Otherwise Stow
  tree-folds `~/.local/bin` into a directory symlink, and tools that install
  there write into the repo.
- Leave binaries that other tools install (claude, git-filter-repo, uv, uvx)
  in `~/.local/bin`, outside the package. They are absolute symlinks, which
  Stow refuses.
- `bin/tests/stow-hygiene/run.sh` checks every package: it fails when a
  package with `tests/` has no `.stow-local-ignore`.
