{
  description = "My nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    catppuccin.url = "github:catppuccin/nix";
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      catppuccin,
    }:
    let
      configuration =
        { pkgs, fonts, ... }:
        {
          networking.hostName = "Gunwoo-iMac";

          environment.systemPackages = [
            pkgs.ansible
            pkgs.asdf-vm
            pkgs.bat
            pkgs.docker
            pkgs.eza
            pkgs.fzf
            pkgs.gh
            pkgs.git
            pkgs.httpie
            pkgs.jq
            pkgs.kubectl
            pkgs.kubectx
            pkgs.kubernetes-helm
            pkgs.lazygit
            pkgs.luarocks-nix
            pkgs.neovim
            pkgs.nixfmt-rfc-style
            pkgs.pnpm
            pkgs.ripgrep
            pkgs.starship
            # pkgs.syncthing
            pkgs.tmux
            pkgs.yq
            pkgs.zoxide
          ];

          homebrew = {
            enable = true;
            casks = [
              "claude"
              "cursor"
              "docker"
              "ghostty"
              "google-chrome"
              "obsidian"
              "raycast"
              "tailscale"
            ];
          };

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";

          # Create /etc/zshrc that loads the nix-darwin environment.
          programs.zsh.enable = true;

          # Set Git commit hash for darwin-version.
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility, please read the changelog before changing.
          # $ darwin-rebuild changelog
          system.stateVersion = 6;

          # The platform the configuration will be used on.
          nixpkgs.hostPlatform = "x86_64-darwin";

          system.primaryUser = "gunwoo";
          users.users.gunwoo = {
            name = "gunwoo";
            home = "/Users/gunwoo";
          };

          system.defaults.trackpad = {
            Clicking = true; # Enable tap to click
          };
          # Optional: also apply it to Bluetooth trackpads
          # system.defaults."com.apple.AppleMultitouchTrackpad".Clicking = true;
          # system.defaults."com.apple.driver.AppleBluetoothMultitouch.trackpad".Clicking = true;
        };
    in
    {
      darwinConfigurations."Gunwoo-iMac" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.gunwoo = {
              imports = [
                ./home.nix
                catppuccin.homeModules.catppuccin
              ];
            };
          }
        ];
      };
    };
}
