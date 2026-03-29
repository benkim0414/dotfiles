# Dotfiles

macOS/Linux dotfiles managed with GNU Stow and Homebrew.

# Commands

## Bootstrap (fresh machine)

```sh
brew bundle --file=Brewfile
mkdir -p ~/.local/bin
stow -t ~ bat bin claude direnv eza ghostty git kitty lazygit mise nvim starship tmux yazi zsh
```

After stowing, register the sequential-thinking MCP server globally so it
is available in all Claude Code projects (not just this repo):

```sh
claude mcp add --scope user sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking
```

This writes to `~/.claude.json`, which is managed by Claude Code and cannot
be stowed.

## Daily workflow

```sh
stow -t ~ <package>          # symlink a package into ~
stow -t ~ -D <package>       # remove a package's symlinks
stow -t ~ -R <package>       # re-stow after restructuring
```

## Adding a new tool

1. Add to Brewfile (`brew` for CLI, `cask` for GUI apps)
2. Create package dir mirroring home layout: `<pkg>/.config/<tool>/...`
3. `stow -t ~ <pkg>`

# Secrets

Bitwarden via direnv (`use_bw` in `.envrc`).
Requires `BW_SESSION` in your shell: `export BW_SESSION="$(bw unlock --raw)"`.
The GitHub MCP server token flows through this mechanism.
Never commit `.env*` files -- they are gitignored and permission-denied in Claude settings.

# Stow gotchas

- **Always pass `-t ~`**. There is no .stowrc; the default target is the parent dir (`~/workspace/`), not `~`.
- **Before stowing `bin`**: run `mkdir -p ~/.local/bin` first. Otherwise Stow tree-folds and creates a directory symlink, which breaks other tools that install into `~/.local/bin`.
- **Stow refuses absolute symlinks**. Files installed by external tools (claude, git-filter-repo, uv, uvx) must NOT be added to the bin package -- leave them as-is in `~/.local/bin`.
- **After restructuring a package dir**, use `stow -t ~ -R <package>` to clean up stale symlinks.

# Package conventions

- Each top-level directory is a Stow package mirroring the home directory layout.
- Config files are edited in-place in the package dir; symlinks make changes live immediately.
- Custom scripts go in `bin/.local/bin/` and must be executable.
- The `claude/` package stows to `~/.claude/` (settings, hooks, and project instructions).

# Brewfile rules

- CLI tools: `brew "<name>"` -- keep sorted alphabetically.
- GUI apps: `cask "<name>"` -- keep sorted alphabetically.
- After adding an entry: `brew bundle --file=Brewfile`.
- No tap entries unless the formula is outside homebrew-core.
