#!/usr/bin/env bash
# Edits to live ~/.claude/ outside the current dotfiles worktree must be flagged.
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Positive: edits to live ~/.claude/ when wt_root is unset or not the dotfiles repo.
assert_file_flagged '/Users/ben/.claude/settings.json' ''
assert_file_flagged '/Users/ben/.claude/hooks/git-safety.sh' ''
assert_file_flagged '/Users/ben/.claude/lib/permission-policy.sh' ''
assert_file_flagged '/Users/ben/.claude/CLAUDE.md' ''
assert_file_flagged '/Users/ben/.claude/statusline.sh' ''
# With wt_root set to a non-dotfiles worktree:
assert_file_flagged '/Users/ben/.claude/hooks/x.sh' '/Users/ben/workspace/other-project'

# Negative: outside ~/.claude/ tree is silent.
assert_file_silent '/Users/ben/workspace/dotfiles/README.md' ''
