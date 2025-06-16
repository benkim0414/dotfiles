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
    file.".local/bin/tmux-sessionizer" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash

        if [[ $# -eq 1 ]]; then
          selected=$1
        else
          selected=$(find ~/workspace ~/.config -mindepth 1 -maxdepth 1 -type d | fzf)
        fi

        if [[ -z $selected ]]; then
          exit 0
        fi

        selected_name=$(basename "$selected" | tr . _)
        tmux_running=$(pgrep tmux)

        if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
          tmux new-session -s $selected_name -c $selected
          exit 0
        fi

        if ! tmux has-session -t=$selected_name 2> /dev/null; then
          tmux new-session -ds $selected_name -c $selected
        fi

        if [[ -z $TMUX ]]; then
          tmux attach-session -t $selected_name
        else
          tmux switch-client -t $selected_name
        fi
      '';
    };

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
      baseIndex = 1;
      keyMode = "vi";
      newSession = true;
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
        resurrect
        sensible
        yank
      ];
      extraConfig = ''
        # Allows programs to receive focus events, improves terminal integration
        set -g focus-events on
        # Prevents gaps in window numbers, reduces need for window management
        set -g renumber-windows on
        # Closes panes when their commands exit, reducing resource usage
        set -g remain-on-exit off
        # Efficiently uses available space when clients of different sizes are attached
        set -g aggressive-resize on

        # Set default command to create a login shell for proper initialization
        set -g default-command "${pkgs.zsh}/bin/zsh -l"

        # Source tmux.conf with <prefix> r.
        bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "source-file ~/.config/tmux/tmux.conf"

        # https://github.com/neovim/neovim/wiki/Building-Neovim#optimized-builds
        # Reduces delay for ESC key, improving vim/neovim responsiveness
        set-option -sg escape-time 10 

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

        # Session navigation with tmux-sessionizer
        bind-key f run-shell "tmux neww tmux-sessionizer"
      '';
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
      options = [ "--cmd cd" ];
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      historySubstringSearch.enable = true;
      completionInit = ''
        # Only regenerate completions once a day to avoid the expensive security check
        autoload -Uz compinit
        if [[ -n ''${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
          compinit -C
        else
          compinit
        fi
        # Skip the compinit that Home Manager might add elsewhere
        compdef() {}
      '';
      initContent = ''
        sz() { source ~/.zshrc }

        export PATH="''${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

        # Append asdf completions to fpath
        fpath=(''${ASDF_DATA_DIR:-$HOME/.asdf}/completions $fpath)

        # Load asdf
        source "${pkgs.asdf-vm}/share/asdf-vm/asdf.sh"

        # Go plugin setup
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
