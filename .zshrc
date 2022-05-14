# Alias to interact with dotfiles instead of the regular git.
# https://www.atlassian.com/git/tutorials/dotfiles
alias config='/usr/local/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'

# zplug
export ZPLUG_HOME=/usr/local/opt/zplug
source $ZPLUG_HOME/init.zsh

zplug 'zsh-users/zsh-syntax-highlighting', defer:2
zplug 'zsh-users/zsh-completions', defer:2
zplug 'zsh-users/zsh-autosuggestions', defer:2

zplug load

for zsh_source in $HOME/.zsh/configs/*.zsh; do
  source $zsh_source
done

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# pyenv
eval "$(pyenv init -)"
# pyenv-virtualenv
eval "$(pyenv virtualenv-init -)"

# nvm
[ -s "/usr/local/opt/nvm/nvm.sh" ] && \. "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/usr/local/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

