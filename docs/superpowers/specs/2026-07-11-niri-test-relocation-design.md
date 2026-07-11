# Niri removal and package-local tests - design

## Goal

Remove obsolete Niri and xdg-desktop-portal configuration from the active dotfiles
surface, and move the remaining repo-level test directories next to the packages
they validate.

## Scope

Remove:

- `niri/.config/niri/config.kdl`
- `xdg-desktop-portal/.config/xdg-desktop-portal/niri-portals.conf`
- the Niri auto-start block in `zsh/.zprofile`

Move:

- `tests/wiki-stage/run.sh` to `bin/tests/wiki-stage/run.sh`
- `tests/zsh-eval-cache/run.sh` to `zsh/tests/eval-cache/run.sh`

Keep:

- `bin/.local/bin/wiki-stage`
- `bin/.local/bin/wiki-stage-install`
- `CLAUDE.md` wiki-stage documentation
- historical wiki-stage specs, plans, and solution notes

## Design

Top-level directories in this repo are GNU Stow packages. The `niri/` and
`xdg-desktop-portal/` directories are dedicated Stow packages whose only purpose
is the retired desktop setup, so removing the tracked files removes those
packages from the active dotfiles set. `zsh/.zprofile` currently has two
responsibilities: starting the SSH agent through keychain and auto-execing
`niri-session` on tty1. The Niri stanza should be removed while the keychain
login behavior remains unchanged.

The `tests/` directory currently holds package-specific shell harnesses. Move
each harness under the package it validates so ownership is visible from the
tree:

- `bin/tests/wiki-stage/run.sh` validates `bin/.local/bin/wiki-stage` and
  `bin/.local/bin/wiki-stage-install`.
- `zsh/tests/eval-cache/run.sh` validates
  `zsh/.config/zsh/eval-cache.zsh` and `.zshrc` wiring.

Both scripts derive the repository root from their own path. After the move,
update the root calculation to walk three directories up from
`bin/tests/wiki-stage` and `zsh/tests/eval-cache`.

## Verification

Run the moved tests from the repository root:

```sh
bash bin/tests/wiki-stage/run.sh
bash zsh/tests/eval-cache/run.sh
```

Also run targeted searches to catch active stale references:

```sh
rg -n '(^|[^[:alnum:]_/.-])tests/(wiki-stage|zsh-eval-cache)' CLAUDE.md bin zsh
rg -n "niri|xdg-desktop-portal" zsh niri xdg-desktop-portal
```

The old-path search intentionally looks for top-level `tests/...` references
only; the approved new `bin/tests/wiki-stage/run.sh` path contains the substring
`tests/wiki-stage` and should not fail verification. Historical docs may still
mention wiki-stage and old test paths as project history. Those references are
intentionally out of scope unless they point to active commands or setup
instructions.

## Risks

The main risk is accidentally removing wiki-stage itself after the scope was
corrected. The implementation should stage explicit paths and inspect the diff
before committing. The unrelated modified `nvim/.config/nvim/lazy-lock.json` in
the main worktree is not part of this change and must remain untouched.
