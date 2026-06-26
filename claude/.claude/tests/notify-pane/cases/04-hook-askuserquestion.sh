# Full hook run: PreToolUse AskUserQuestion, TMUX_PANE empty, TMUX set.
# The resolver recovers the pane id and the marker block writes the marker.
source "$TEST_HOME/helpers.sh"
setup_mocks
trap teardown_mocks EXIT

SENT=999042
# The piped `bash "$HOOK"` process's parent is THIS case shell ($$).
{ printf '%s %s\n' "$$" "$SENT"; printf '%s 1\n' "$SENT"; } > "$TMPROOT/ps.txt"
printf '%s\t%s\n' "$SENT" "%TESTPANE" > "$TMPROOT/panes.txt"
export MOCK_PS_FILE="$TMPROOT/ps.txt" MOCK_PANES_FILE="$TMPROOT/panes.txt"
unset TMUX_PANE; export TMUX="fake"
export XDG_CACHE_HOME="$TMPROOT/cache"

echo '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","session_id":"sess-aq","cwd":"/x/proj"}' \
  | bash "$HOOK"

marker="$TMPROOT/cache/claude/attention/%TESTPANE"
assert_file "$marker"
assert_grep '^notification_type=ask_user_question$' "$marker"
assert_grep '^pane_id=%TESTPANE$' "$marker"
