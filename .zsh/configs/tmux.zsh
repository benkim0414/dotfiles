ensure_tmux_is_running() {
  if is_not_inside_tmux; then
    tat
  fi
}

is_not_inside_tmux() {
  [[ -z "$TMUX" ]]
}
