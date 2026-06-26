# TMUX_PANE already set -> returned verbatim (Notification-path regression).
source "$TEST_HOME/helpers.sh"
source "$LIB"
export TMUX_PANE="%55" TMUX="fake"
got="$(notify_resolve_pane_id)"
assert_eq "$got" "%55" "env pane returned verbatim"
