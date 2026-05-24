HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
mkdir -p "${HISTFILE:h}"
HISTSIZE=50000
SAVEHIST=50000

if command -v keychain &>/dev/null && [[ -t 0 && ( -z ${SSH_AUTH_SOCK-} || ! -S ${SSH_AUTH_SOCK} ) ]]; then
    eval "$(keychain --eval --quiet ~/.ssh/id_ed25519)"
fi

if [[ -n ${TMUX-} && ( -z ${WAYLAND_DISPLAY-} || ${XDG_SESSION_TYPE-} == tty ) ]] \
    && command -v systemctl &>/dev/null; then
    while IFS='=' read -r name value; do
        case "$name" in
            XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|XDG_SESSION_DESKTOP|HYPRLAND_INSTANCE_SIGNATURE)
                export "$name=$value"
                ;;
        esac
    done < <(systemctl --user show-environment 2>/dev/null)
fi

setopt EXTENDED_HISTORY          # Record timestamp and duration
setopt HIST_IGNORE_ALL_DUPS      # Remove older duplicate entries
setopt HIST_IGNORE_SPACE         # Don't record entries starting with space
setopt HIST_REDUCE_BLANKS        # Remove unnecessary blanks
setopt HIST_VERIFY               # Don't execute immediately on history expansion
setopt INC_APPEND_HISTORY        # Add commands to history immediately
unsetopt SHARE_HISTORY           # Manual import via fc -RI gives predictable refresh timing

autoload -Uz add-zsh-hook
_import_appended_history() {
  [[ -r "$HISTFILE" ]] && fc -RI
}
add-zsh-hook precmd _import_appended_history

setopt COMBINING_CHARS           # Handle combining Unicode characters correctly
setopt COMPLETE_IN_WORD          # Complete from both ends of word
setopt ALWAYS_TO_END             # Move cursor to end after completion
setopt MENU_COMPLETE             # Show completion menu on tab
setopt AUTO_MENU                 # Auto-show completion menu
setopt EXTENDED_GLOB             # Extended glob patterns
setopt INTERACTIVE_COMMENTS      # Allow # comments in interactive shell
setopt NO_HASH_CMDS              # Disable command hashing (needed for mise)
setopt NO_HASH_DIRS              # Disable directory hashing (needed for mise)
unsetopt BEEP                    # No error beep

bindkey -v
KEYTIMEOUT=1

bindkey -M viins "^a" beginning-of-line
bindkey -M viins "^e" end-of-line
bindkey -M viins "^p" history-search-backward
bindkey -M viins "^n" history-search-forward
bindkey -M viins "^[[A" history-search-backward
bindkey -M viins "^[[B" history-search-forward
bindkey -M viins "^[[C" forward-char
bindkey -M viins "^[[D" backward-char

autoload -Uz compinit
compinit -C
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=* l:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' file-list all
zstyle ':completion:*' list-prompt ''
zstyle ':completion:*' select-prompt ''

source ~/.antidote/antidote.zsh

_antidote_static="${ZDOTDIR:-$HOME}/.zsh_plugins.zsh"
[[ -e "$_antidote_static" && ! -s "$_antidote_static" ]] && rm -f "$_antidote_static"
unset _antidote_static

antidote load

_eval_cache() {
  local name="$1"; shift
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/eval-cache-${name}.zsh"
  local bin_path
  bin_path="$(command -v "$1" 2>/dev/null)"
  if [[ ! -s "$cache" || ( -n "$bin_path" && "$bin_path" -nt "$cache" ) ]]; then
    mkdir -p "${cache:h}"
    "$@" > "$cache"
  fi
  source "$cache"
}

_eval_cache fzf fzf --zsh
_eval_cache zoxide zoxide init zsh --cmd cd

eval "$(starship init zsh)"
eval "$(mise activate zsh)"

# Per-machine env (gitignored on each machine, sourced if present)
[ -r ~/.openclaw/.env ] && set -a && . ~/.openclaw/.env && set +a

# Aliases
_zsh_aliases="${ZDOTDIR:-$HOME}/.zsh_aliases"
[ -r "$_zsh_aliases" ] && source "$_zsh_aliases"
unset _zsh_aliases

if (( $+commands[kubectl] )); then
  source <(kubectl completion zsh)
  if (( $+functions[__start_kubectl] )); then
    compdef __start_kubectl k
  elif (( $+functions[_kubectl] )); then
    compdef _kubectl k
  fi
fi

sz() { source ~/.zshrc }

bwu() { export BW_SESSION="$(bw unlock --raw)" }
