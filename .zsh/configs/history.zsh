# The path/location of the history file.
if [ -z "$HISTFILE" ]; then
  HISTFILE=$HOME/.zsh_history
fi

# The number of commands that are loaded into memory from the history file.
HISTSIZE=10000
# The number of commands that are stored in the zsh history file.
SAVEHIST=10000

# If this is set, zsh sessions will append their history list to the history
# file, rather than replace it.
setopt APPEND_HISTORY
# Save each command’s beginning timestamp (in seconds since the epoch) and the
# duration (in seconds) to the history file. The format of this prefixed data is:
# ': <beginning time>:<elapsed seconds>;<command>'.
setopt EXTENDED_HISTORY
# If the internal history needs to be trimmed to add the current command line,
# setting this option will cause the oldest history event that has a duplicate
# to be lost before losing a unique event from the list.
setopt HIST_EXPIRE_DUPS_FIRST
# Do not enter command lines into the history list if they are duplicates of
# the previous event.
setopt HIST_IGNORE_DUPS
# Remove command lines from the history list when the first character on the
# line is a space, or when one of the expanded aliases contains a leading space.
setopt HIST_IGNORE_SPACE
# Whenever the user enters a line with history expansion, don’t execute the
# line directly; instead, perform history expansion and reload the line into
# the editing buffer.
setopt HIST_VERIFY
# This option works like APPEND_HISTORY except that new history lines are added
# to the $HISTFILE incrementally (as soon as they are entered), rather than
# waiting until the shell exits.
setopt INC_APPEND_HISTORY
# This option both imports new commands from the history file, and also causes
# your typed commands to be appended to the history file (the latter is like
# specifying INC_APPEND_HISTORY, which should be turned off if this option is
# in effect).
setopt SHARE_HISTORY
