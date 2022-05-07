# Alias to interact with dotfiles instead of the regular git.
# https://www.atlassian.com/git/tutorials/dotfiles
alias config='/usr/local/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

