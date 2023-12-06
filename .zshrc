# Alias to interact with dotfiles instead of the regular git.
# https://www.atlassian.com/git/tutorials/dotfiles
alias config="$(which git) --git-dir=$HOME/.cfg/ --work-tree=$HOME"

# zplug
export ZPLUG_HOME="$(brew --prefix zplug)"
source $ZPLUG_HOME/init.zsh

zplug "mafredri/zsh-async", from:"github", use:"async.zsh"
zplug 'zsh-users/zsh-syntax-highlighting', defer:2
zplug 'zsh-users/zsh-completions', defer:2
zplug 'zsh-users/zsh-autosuggestions', defer:2

zplug load

for zsh_source in $HOME/.zsh/configs/*.zsh; do
  source $zsh_source
done

ensure_tmux_is_running

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

sz() { source ~/.zshrc }

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# pnpm
export PNPM_HOME="/Users/gunwoo/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end