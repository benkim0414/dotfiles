# Bash commands
- `brew install <tool>`: Install a specific CLI tool or package
- `brew install --cask <app>`: Install a specific GUI application
- `stow <package>`: Create symlinks for specific package configuration (e.g., `stow nvim`)
- `stow *`: Create symlinks for all package configurations
- `brew bundle --file=Brewfile`: Bulk install all packages (fresh system setup)

# Configuration
- CLI tools: Add to `brew` section in `Brewfile` (optional, for tracking)
- GUI macOS apps: Add to `cask` section in `Brewfile` (optional, for tracking)
- Tool-specific config: Edit files in respective directories (nvim/, git/, starship/, etc.)
- Custom scripts: Add to `bin/.local/bin/` directory

# Package Structure
Each tool has its own directory that mirrors the home directory structure:
- `nvim/.config/nvim/`: Neovim configuration
- `git/.gitconfig`: Git global configuration
- `starship/.config/starship.toml`: Starship prompt configuration
- `zsh/.zshrc`: Zsh shell configuration
- `bin/.local/bin/`: Custom scripts and binaries

# Workflow
- Think harder with sequential-thinking MCP before making any changes
- **Adding new tool**: `brew install <tool>` → create config directory structure → add config files → `stow <tool>`
- **Modifying existing configs**: Edit files directly in dotfiles directories (changes are immediate via symlinks)
- **Verify changes**: Test the tool/configuration to ensure it works correctly
