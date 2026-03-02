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
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
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

export SSH_AUTH_SOCK=~/.bitwarden-ssh-agent.sock
