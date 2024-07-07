export EZA_ICONS_AUTO=true
# List only directories
alias ld='eza -lD'
# List only files
alias lf='eza -lf --color=always | grep -v /'
# List only hidden files
alias lh='eza -dl .* --group-directories-first'
# List everything with directories first
alias ls='eza -al --color=always --group-directories-first'
# List everything sorted by time updated
alias lt='eza -al --sort=modified'
