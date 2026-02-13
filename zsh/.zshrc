HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=50000
SAVEHIST=50000

setopt EXTENDED_HISTORY          # Record timestamp and duration
setopt HIST_IGNORE_ALL_DUPS      # Remove older duplicate entries
setopt HIST_IGNORE_SPACE         # Don't record entries starting with space
setopt INC_APPEND_HISTORY        # Add commands to history immediately
setopt SHARE_HISTORY             # Share history between sessions

bindkey "^a" beginning-of-line
bindkey "^e" end-of-line
bindkey "^p" history-search-backward
bindkey "^n" history-search-forward

autoload -Uz compinit
compinit

source ~/.antidote/antidote.zsh
antidote load

source <(fzf --zsh)

if [[ $- == *i* ]]; then
  eval "$(zoxide init zsh --cmd cd)"
fi

eval "$(starship init zsh)"

. ${ASDF_DATA_DIR:-$HOME/.asdf}/plugins/golang/set-env.zsh

alias vi="nvim"
alias vim="nvim"

alias ld="eza -lD"
alias lf="eza -lf --color=always | grep -v /"
alias lh="eza -dl .* --group-directories-first"
alias ls="eza -a --color=always --group-directories-first"
alias lt="eza -al --sort=modified"

alias lg="lazygit"

sz() { source ~/.zshrc }
