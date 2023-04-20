# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/usr/local/bin:$PATH"

export PATH="$HOME/bin:$PATH"

# Go
export PATH="$(go env GOPATH)/bin:$PATH"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# nvm
export NVM_DIR="$HOME/.nvm"

