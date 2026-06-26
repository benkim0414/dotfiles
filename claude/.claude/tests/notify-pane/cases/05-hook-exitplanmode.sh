# Full hook run: PreToolUse ExitPlanMode -> plan_approval marker.
source "$TEST_HOME/helpers.sh"
setup_mocks
trap teardown_mocks EXIT

SENT=999043
{ printf '%s %s\n' "$$" "$SENT"; printf '%s 1\n' "$SENT"; } > "$TMPROOT/ps.txt"
printf '%s\t%s\n' "$SENT" "%PLANPANE" > "$TMPROOT/panes.txt"
export MOCK_PS_FILE="$TMPROOT/ps.txt" MOCK_PANES_FILE="$TMPROOT/panes.txt"
unset TMUX_PANE; export TMUX="fake"
export XDG_CACHE_HOME="$TMPROOT/cache"

echo '{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","session_id":"sess-pm","cwd":"/x/proj"}' \
  | bash "$HOOK"

marker="$TMPROOT/cache/claude/attention/%PLANPANE"
assert_file "$marker"
assert_grep '^notification_type=plan_approval$' "$marker"
