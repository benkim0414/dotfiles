#!/usr/bin/env bash
# Regression: edits inside the current worktree must always be silent,
# even when the path matches a safety-critical pattern segment.
set -uo pipefail
source "$TEST_HOME/helpers.sh"

WT=/Users/ben/workspace/dotfiles/.claude/worktrees/claude-permissions-hardening
assert_file_silent "$WT/claude/.claude/settings.base.json" "$WT"
assert_file_silent "$WT/claude/.claude/hooks/git-safety.sh"  "$WT"
assert_file_silent "$WT/claude/.claude/lib/permission-policy.sh" "$WT"
assert_file_silent "$WT/claude/.claude/CLAUDE.md" "$WT"
assert_file_silent "$WT/docs/superpowers/plans/x.md" "$WT"

# Edits to the dotfiles source tree (outside any worktree) also stay silent,
# because the source IS the canonical edit channel for stowed dotfiles.
assert_file_silent /Users/ben/workspace/dotfiles/claude/.claude/settings.base.json ''
assert_file_silent /Users/ben/workspace/dotfiles/zsh/.zshrc ''
