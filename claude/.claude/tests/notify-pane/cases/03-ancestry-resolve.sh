# TMUX_PANE empty + TMUX set: resolve pane id by matching an ancestor pid
# against the tmux pane_pid table.
source "$TEST_HOME/helpers.sh"
setup_mocks
trap teardown_mocks EXIT
source "$LIB"

SENT=999001
# Ancestry: this shell's $PPID -> SENT (a fake pane_pid) -> init.
{ printf '%s %s\n' "$PPID" "$SENT"; printf '%s 1\n' "$SENT"; } > "$TMPROOT/ps.txt"
printf '%s\t%s\n' "$SENT" "%TESTPANE" > "$TMPROOT/panes.txt"
export MOCK_PS_FILE="$TMPROOT/ps.txt" MOCK_PANES_FILE="$TMPROOT/panes.txt"
unset TMUX_PANE; export TMUX="fake"

got="$(notify_resolve_pane_id)"
assert_eq "$got" "%TESTPANE" "ancestry resolves pane id"
