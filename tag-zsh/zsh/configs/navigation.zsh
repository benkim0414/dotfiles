unsetopt AUTO_CD

cdpath=(
  $HOME/workspace \
  $HOME
)

function cdup() {
  cd "$(git rev-parse --show-toplevel)"
}
