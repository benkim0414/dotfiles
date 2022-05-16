fpath=(~/.zsh/completion $fpath)

autoload -U compinit
compinit

# case-insensitive (all), partial-word and then substring completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

zstyle ':completion:*:*:git:*' script ~/.zsh/completion/git-completion.bash

alias k=kubectl
complete -F __start_kubectl k

