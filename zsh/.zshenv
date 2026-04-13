export EDITOR="nvim"
export VISUAL="nvim"
export SUDO_EDITOR="$EDITOR"

export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

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

# SSH agent socket: ensure every shell (including new tmux panes) finds
# the running ssh-agent.
# - Linux: systemd user service manages the agent; just point to its socket.
# - macOS: the launchd agent is unreachable in tmux and SSH sessions.
#   Use a fixed socket and start our own agent if none is reachable.
#   UseKeychain in ssh_config reads the passphrase from Keychain on first
#   use, so the agent only needs to be seeded once per boot.
if [[ "$OSTYPE" == "linux"* ]]; then
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    ssh-add -l &>/dev/null
    if [[ $? -eq 2 ]]; then
        rm -f "$SSH_AUTH_SOCK"
        eval "$(ssh-agent -a "$SSH_AUTH_SOCK")" >/dev/null
    fi
fi

# Suppress zoxide's doctor diagnostic in non-interactive shells (e.g. Claude
# Code's Bash tool) where chpwd_functions is not restored from the snapshot.
# In interactive shells this is harmless: the chpwd hook check would pass anyway.
export _ZO_DOCTOR=0

# Claude Code: defer MCP tool definitions and load them on demand via ToolSearch.
# Reduces context consumption when many MCP servers are registered.
# "auto" loads upfront only if tools consume <10% of context, else defers.
export ENABLE_TOOL_SEARCH=auto
