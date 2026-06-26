# TMUX set but no ancestor pid matches any tmux pane_pid -> resolve to empty
# (the safety net that prevents writing a wrong/empty-named marker).
source "$TEST_HOME/helpers.sh"
setup_mocks
trap teardown_mocks EXIT
source "$LIB"

# Ancestry chain that never reaches a pane_pid: $PPID -> 1.
printf '%s 1\n' "$PPID" > "$TMPROOT/ps.txt"
# A pane exists, but its pane_pid is NOT in the ancestry chain.
printf '%s\t%s\n' "888777" "%OTHERPANE" > "$TMPROOT/panes.txt"
export MOCK_PS_FILE="$TMPROOT/ps.txt" MOCK_PANES_FILE="$TMPROOT/panes.txt"
unset TMUX_PANE; export TMUX="fake"

got="$(notify_resolve_pane_id)"
assert_eq "$got" "" "no ancestor match -> empty"
