# Commands

- `brew install <tool>`: Install a CLI tool
- `brew install --cask <app>`: Install a GUI application
- `brew bundle --file=Brewfile`: Bulk install all packages (fresh system setup)
- `stow -t ~ <package>`: Symlink a package's config into home
- `stow -t ~ -D <package>`: Remove a package's symlinks from home

# Package Structure

Each directory mirrors the home directory layout and is managed with GNU Stow:

- `bat/`: bat config
- `bin/.local/bin/`: Custom scripts and binaries
- `claude/.claude/`: Claude Code config, hooks, and settings
- `direnv/`: direnv config
- `eza/`: eza config
- `ghostty/`: Ghostty terminal config
- `git/.gitconfig`: Git global config
- `kitty/`: Kitty terminal config
- `lazygit/`: lazygit config
- `nvim/.config/nvim/`: Neovim config
- `starship/.config/starship.toml`: Starship prompt config
- `tmux/`: tmux config
- `yazi/`: yazi config
- `zsh/.zshrc`: Zsh config

# Configuration

- CLI tools: Add to `brew` section in `Brewfile`
- GUI apps: Add to `cask` section in `Brewfile`
- Tool config: Edit files directly in the respective package directory (changes apply immediately via symlinks)
- Custom scripts: Add to `bin/.local/bin/`

# Workflow

- **Adding a new tool**: `brew install <tool>` → create package directory → add config files → `stow -t ~ <package>`
- **Modifying existing config**: Edit files in the package directory; symlinks make changes live immediately
- **Verify**: Test the tool after any config change
