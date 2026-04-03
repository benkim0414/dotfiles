HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=50000
SAVEHIST=50000

setopt EXTENDED_HISTORY          # Record timestamp and duration
setopt HIST_IGNORE_ALL_DUPS      # Remove older duplicate entries
setopt HIST_IGNORE_SPACE         # Don't record entries starting with space
setopt HIST_REDUCE_BLANKS        # Remove unnecessary blanks
setopt HIST_VERIFY               # Don't execute immediately on history expansion
setopt INC_APPEND_HISTORY        # Add commands to history immediately
setopt SHARE_HISTORY             # Share history between sessions

setopt COMBINING_CHARS           # Handle combining Unicode characters correctly
setopt COMPLETE_IN_WORD          # Complete from both ends of word
setopt ALWAYS_TO_END             # Move cursor to end after completion
setopt MENU_COMPLETE             # Show completion menu on tab
setopt AUTO_MENU                 # Auto-show completion menu
setopt AUTO_CD                   # cd by typing directory name
setopt EXTENDED_GLOB             # Extended glob patterns
setopt INTERACTIVE_COMMENTS      # Allow # comments in interactive shell
setopt NO_HASH_CMDS              # Disable command hashing (needed for mise)
setopt NO_HASH_DIRS              # Disable directory hashing (needed for mise)
unsetopt BEEP                    # No error beep

bindkey -e
bindkey "^a" beginning-of-line
bindkey "^e" end-of-line
bindkey "^p" history-search-backward
bindkey "^n" history-search-forward
bindkey "^[[A" history-search-backward
bindkey "^[[B" history-search-forward
bindkey "^[[C" forward-char
bindkey "^[[D" backward-char

autoload -Uz compinit
compinit -C
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=* l:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' file-list all
zstyle ':completion:*' list-prompt ''
zstyle ':completion:*' select-prompt ''

source ~/.antidote/antidote.zsh
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

alias vi="nvim"
alias vim="nvim"

alias ld="eza -lD"
alias lf="eza -lf --color=always | grep -v /"
alias lh="eza -dl .* --group-directories-first"
alias ls="eza -a --color=always --group-directories-first"
alias lt="eza -al --sort=modified"

alias lg="lazygit"

# Claude Code
alias cc="claude"
alias cca="claude --permission-mode auto"
alias ccc="claude --continue"
alias ccr="claude --resume"
alias ccw="claude --worktree --tmux"
alias ccp="claude --print"

sz() { source ~/.zshrc }

bwu() { export BW_SESSION="$(bw unlock --raw)" }
