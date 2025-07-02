# Bash commands
- `sudo darwin-rebuild switch --flake ~/workspace/dotfiles/nix/darwin`: Apply changes to macOS system based on nix-darwin configuration 

# Configuration
- GUI macOS apps: Add to `homebrew.casks` section in `nix/darwin/flake.nix`
- System packages: Add to `environment.systemPackages` in `nix/darwin/flake.nix`
- Home-manager options: Configure in `nix/darwin/home.nix`

# NixOS MCP Tools
- `darwin_search(query)`: Search nix-darwin macOS configuration options
- `darwin_info(name)`: Get detailed info about specific darwin option
- `darwin_list_options()`: Browse all 21 darwin configuration categories
- `home_manager_search(query)`: Search home-manager user configuration options
- `home_manager_info(name)`: Get detailed info about specific home-manager option
- `home_manager_list_options()`: Browse all 131 home-manager configuration categories

# Workflow
- Think harder with sequential-thinking MCP before making any changes
- Rebuild the system to apply changes
- Verify applied changes
