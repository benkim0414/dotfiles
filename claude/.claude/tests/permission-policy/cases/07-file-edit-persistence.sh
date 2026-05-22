#!/usr/bin/env bash
# Shell init / persistence file edits via live paths should flag.
# Dotfiles source paths (zsh/.zshrc inside dotfiles) are not on this list
# and stay silent naturally.
set -uo pipefail
source "$TEST_HOME/helpers.sh"

assert_file_flagged '/Users/ben/.zshrc' ''
assert_file_flagged '/Users/ben/.bashrc' ''
assert_file_flagged '/Users/ben/.gitconfig' ''
assert_file_flagged '/Users/ben/Library/LaunchAgents/com.example.plist' ''
assert_file_flagged '/Users/ben/.config/launchd/foo.plist' ''
assert_file_flagged '/etc/crontab' ''

# Dotfiles source edits go through repo paths -- those don't match the
# live-path patterns and stay silent.
assert_file_silent '/Users/ben/workspace/dotfiles/zsh/.zshrc' '/Users/ben/workspace/dotfiles'
assert_file_silent '/tmp/notes.md' ''
