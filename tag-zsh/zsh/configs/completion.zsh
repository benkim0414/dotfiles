fpath=(~/.zsh/completion $fpath)

# With the -U flag, alias expansion is suppressed when the function is loaded.
# The flag -z mark the function to be autoloaded using the zsh style.
# The flag +X attempts to load each name as an autoloaded function, but does
# not execute it.
autoload -Uz +X compinit
compinit

# case-insensitive (all), partial-word and then substring completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
