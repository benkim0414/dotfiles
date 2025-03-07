{ config, pkgs, ... }:
let
  inherit (config.lib.file) mkOutOfStoreSymlink;
in
{
  home = {
    stateVersion = "24.05";
    homeDirectory = "/Users/gunwoo";
    username = "gunwoo";
    packages = [
      pkgs.nerd-fonts.symbols-only
    ];
    file.".local/bin".source = mkOutOfStoreSymlink "/Users/gunwoo/workspace/dotfiles/bin";
    sessionPath = [
      "$HOME/.local/bin"
    ];
  };

  programs.home-manager.enable = true;

  xdg.enable = true;
  xdg.configFile.nvim.source = mkOutOfStoreSymlink "/Users/gunwoo/workspace/dotfiles/nvim";
  xdg.configFile."ghostty/config".source =
    mkOutOfStoreSymlink "/Users/gunwoo/workspace/dotfiles/ghostty/config";

  programs = {
    bat.enable = true;

    eza = {
      enable = true;
      enableZshIntegration = true;
      extraOptions = [
        "--color=always"
        "--group-directories-first"
      ];
      icons = "auto";
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      tmux.enableShellIntegration = true;
    };

    git = {
      enable = true;
      userName = "Gunwoo Ben Kim";
      userEmail = "benkim0414@gmail.com";
      extraConfig = {
        core = {
          editor = "nvim";
        };
        init = {
          defaultBranch = "main";
        };
        pull = {
          ff = "only";
        };
        push = {
          default = "upstream";
        };
      };
    };

    go.enable = true;

    lazygit = {
      enable = true;
      settings = {
        gui.theme = {
          activeBorderColor = [
            "#89b4fa"
            "bold"
          ];
          inactiveBorderColor = [ "#a6adc8" ];
          optionsTextColor = [ "#89b4fa" ];
          selectedLineBgColor = [ "#313244" ];
          cherryPickedCommitBgColor = [ "#45475a" ];
          cherryPickedCommitFgColor = [ "#89b4fa" ];
          unstagedChangesColor = [ "#f38ba8" ];
          defaultFgColor = [ "#cdd6f4" ];
          searchingActiveBorderColor = [ "#f9e2af" ];
        };
      };
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = pkgs.lib.importTOML ../../starship.toml;
    };

    tmux = {
      enable = true;
      disableConfirmationPrompt = true;
      keyMode = "vi";
      newSession = true;
      secureSocket = true;
      shell = "${pkgs.zsh}/bin/zsh";
      shortcut = "s";
      terminal = "screen-256color";
      plugins = with pkgs.tmuxPlugins; [
        vim-tmux-navigator
        {
          plugin = catppuccin;
          extraConfig = ''
            set -g status-right-length 100
            set -g status-left-length 100
            set -g status-left ""

            set -g @catppuccin_window_left_separator ""
            set -g @catppuccin_window_right_separator " "
            set -g @catppuccin_window_middle_separator " █"
            set -g @catppuccin_window_number_position "right"

            set -g @catppuccin_window_default_fill "number"
            set -g @catppuccin_window_default_text "#W"

            set -g @catppuccin_window_current_fill "number"
            set -g @catppuccin_window_current_text "#W"

            set -g @catppuccin_status_modules_right "session host"
            set -g @catppuccin_status_left_separator " "
            set -g @catppuccin_status_middle_separator ""
            set -g @catppuccin_status_right_separator ""
            set -g @catppuccin_status_fill "icon"
            set -g @catppuccin_status_connect_separator "no"

            set -g @catppuccin_directory_text "#{pane_current_path}"
          '';
        }
      ];
      extraConfig = ''
        # Source tmux.conf with <prefix> r.
        bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "source-file ~/.config/tmux/tmux.conf"

        # https://github.com/neovim/neovim/wiki/Building-Neovim#optimized-builds
        set-option -sg escape-time 10

        set-option -g focus-events on

        # Create a new pane by splitting `target-pane`: -h does a
        # horizontal split and -v a vertical split; if neither is
        # specified, -v is assumed.
        bind-key s split-window -v -c "#{pane_current_path}"
        bind-key v split-window -h -c "#{pane_current_path}"

        # Create a new window in the directory of the current pane.
        bind-key c new-window -c "#{pane_current_path}"

        # If on, when a window is closed in a session, automatically
        # renumber the other windows in numerical order.
        set-option -g renumber-windows on
        # Break src-pane off from its containing window to make it
        # the only pane in dst-window.
        # If -d is given, the new window does not become the current window.
        bind-key b break-pane -d

        # The default key bindings include <Ctrl-l> which is the readline key binding
        # for clearing the screen.
        # With this enabled you can use <prefix> C-l to clear the screen.
        bind-key C-l send-keys 'C-l'

        # Use vi key binding in copy mode.
        set-option -wg mode-keys vi
        bind-key -T copy-mode-vi v send-keys -X begin-selection
        bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy"
        bind-key -T copy-mode-vi 0 send-keys -X back-to-indentation
        bind-key -T copy-mode-vi / command-prompt -i -p "search down" "send-keys -X search-forward-incremental '%%%'"
        bind-key -T copy-mode-vi ? command-prompt -i -p "search up" "send-keys -X search-backward-incremental '%%%'"

        # Resize the active pane.
        bind-key -n S-Left resize-pane -L 2
        bind-key -n S-Right resize-pane -R 2
        bind-key -n S-Down resize-pane -D 1
        bind-key -n S-Up resize-pane -U 1
        bind-key -n C-Left resize-pane -L 10
        bind-key -n C-Right resize-pane -R 10
        bind-key -n C-Down resize-pane -D 5
        bind-key -n C-Up resize-pane -U 5
      '';
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
      options = [ "--cmd cd" ];
    };

    zsh = {
      enable = true;
      antidote = {
        enable = true;
        plugins = [
          "zsh-users/zsh-syntax-highlighting"
          "zsh-users/zsh-completions"
          "zsh-users/zsh-autosuggestions"
          "zsh-users/zsh-history-substring-search"
          "ohmyzsh/ohmyzsh path:plugins/git"
        ];
      };
      initExtra = ''
        sz() { source ~/.zshrc }
        source "${pkgs.asdf-vm}/share/asdf-vm/asdf.sh"
        source "${pkgs.asdf-vm}/share/asdf-vm/completions/asdf.bash"
        source ~/.asdf/plugins/golang/set-env.zsh
      '';
      shellAliases = {
        cat = "bat";
        k = "kubectl";
        ls = "eza";
        lg = "lazygit";
        pn = "pnpm";
        vi = "nvim";
      };
    };
  };

  catppuccin = {
    enable = true;
    flavor = "mocha";
  };
}
