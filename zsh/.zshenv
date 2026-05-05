export EDITOR="nvim"
export VISUAL="nvim"
export SUDO_EDITOR="$EDITOR"

export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# Hermes runtime home is the versioned workspace checkout; keeping this in
# .zshenv makes non-interactive zsh invocations use the same config and skills.
export HERMES_HOME="$HOME/workspace/hermes"

export PATH="$HOME/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ -x /opt/homebrew/bin/brew ]]; then  # Apple Silicon
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then   # Intel Mac
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

export FZF_DEFAULT_OPTS=" \
--color=bg+:#313244,bg:#1E1E2E,spinner:#F5E0DC,hl:#F38BA8 \
--color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
--color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
--color=selected-bg:#45475A \
--color=border:#313244,label:#CDD6F4"

export EZA_CONFIG_DIR="$XDG_CONFIG_HOME/eza"
export EZA_ICONS_AUTO=true

export BAT_THEME="Catppuccin Mocha"

# keychain writes the agent socket path here on login; all shells source it
# so tmux panes and non-login shells find the same agent without re-prompting.
[[ -f "$HOME/.keychain/$HOST-sh" ]] && source "$HOME/.keychain/$HOST-sh"

# Suppress zoxide's doctor diagnostic in non-interactive shells (e.g. Claude
# Code's Bash tool) where chpwd_functions is not restored from the snapshot.
# In interactive shells this is harmless: the chpwd hook check would pass anyway.
export _ZO_DOCTOR=0

# Claude Code: defer MCP tool definitions and load them on demand via ToolSearch.
# Reduces context consumption when many MCP servers are registered.
# "auto" loads upfront only if tools consume <10% of context, else defers.
export ENABLE_TOOL_SEARCH=auto
