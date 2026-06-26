# Not inside tmux -> nothing resolvable.
source "$TEST_HOME/helpers.sh"
source "$LIB"
unset TMUX_PANE TMUX 2>/dev/null || true
got="$(notify_resolve_pane_id)"
assert_eq "$got" "" "no tmux -> empty"
