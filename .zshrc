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

fpath=(~/.zsh $fpath)
autoload -U compinit
compinit

zstyle ':completion:*:*:git:*' script ~/.git-completion.bash

# If set, parameter expansion, command substitution and arithmetic expansion
# are performed in prompts. Substitutions within prompts do not affect the
# command status.
setopt PROMPT_SUBST
. ~/git-prompt.sh
PROMPT="%n@%m:%~\$(__git_ps1 '(%s)')%# "

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

