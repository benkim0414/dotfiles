# Dotfiles

macOS/Linux dotfiles managed with GNU Stow and Homebrew. Each top-level
directory is a Stow package that mirrors the home directory layout.

Package-specific notes are path-scoped rules in `.claude/rules/`. Each loads
when you touch files in its package.

# Stow

```sh
stow -t ~ <package>          # symlink a package into ~
stow -t ~ -D <package>       # remove a package's symlinks
stow -t ~ -R <package>       # re-stow after restructuring a package
```

- Always pass `-t ~`. There is no `.stowrc`, so the default target is the
  parent dir (`~/workspace/`).
- Stow only from the main checkout, after merge. Stowing from
  `.claude/worktrees/<name>/` links into a directory that disappears with the
  worktree.
- Edit config files in place in the package. The symlinks make changes live.

# Adding a tool

1. Add it to `Brewfile`: `brew "<name>"` for CLI, `cask "<name>"` for GUI.
   Keep each group sorted. Add a `tap` only for a formula outside
   homebrew-core.
2. Run `brew bundle --file=Brewfile`.
3. Create the package dir in the home layout: `<pkg>/.config/<tool>/...`.
4. `stow -t ~ <pkg>`.

# Package conventions

- Machine-specific settings go in untracked `~/.zshenv.local`,
  `~/.zprofile.local` and `~/.gitconfig.local`. The shared configs load them
  only if present. They live outside the repo.
- Tests live in their package: `<pkg>/tests/<name>/run.sh`. The `claude`
  package nests them at `claude/.claude/tests/<name>/run.sh`, because the
  whole package stows into `~/.claude/`.
- Suites share an `ok`/`bad` counter and `exit 0`/`exit 1`. "Could not
  check" must look different from "passed": when a file is missing or a
  `grep`/`git`/`jq` call fails, call `bad`.
- A package with `tests/` needs a `.stow-local-ignore` holding `^/tests$`, or
  Stow links it into `~/tests`. `bin/tests/stow-hygiene/run.sh` checks this.
- A `.stow-local-ignore` replaces Stow's default ignore list. Restate the
  defaults you still need (`git/.stow-local-ignore` restates `\.git`).

# Secrets

Other repos load secrets through mise:

- Bitwarden: `mise-load-bw` resolves `.env.bw` (`VAR=uuid:field`) into a
  cached `.env.local`. In `.mise.toml`, set `[env] _.file = [".env.local"]`
  and `[tasks.secrets] run = "mise-load-bw"`. Run `mise run secrets` after
  first clone or secret rotation.
- 1Password: the same pattern with `mise-load-op` and `.env.op`.
- Use `_.file`, not `_.source`: mise re-runs `_.source` scripts on every
  prompt.
- `.env*` and `.mise.local.toml` stay uncommitted (gitignored).

# RTK

RTK (`brew "rtk"`) is a `PreToolUse` hook on `Bash` (`rtk hook claude`). It
compacts output of git, test runners and builds. Failed runs keep full
output: `rtk recall <id>`. Run a command raw with `rtk bypass <cmd>`.
Defaults only; no config is stowed.
