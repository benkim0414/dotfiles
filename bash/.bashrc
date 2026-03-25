#!/usr/bin/env bash
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Omarchy defaults (shell options, aliases, starship, zoxide, fzf, mise)
source ~/.local/share/omarchy/default/bash/rc

# ---------------------------------------------------------------------------
# User overrides
# ---------------------------------------------------------------------------

# Locale
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

# XDG base dirs
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# Editor
export EDITOR="nvim"
export VISUAL="nvim"
export SUDO_EDITOR="$EDITOR"

# PATH additions
export PATH="$HOME/bin:$PATH"

# History (override Omarchy's HISTSIZE=32768 and HISTCONTROL=ignoreboth)
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
HISTSIZE=50000
HISTFILESIZE=50000
HISTTIMEFORMAT="%F %T "
# erasedups: remove older duplicates anywhere in history (stronger than ignoredups)
HISTCONTROL=erasedups:ignorespace
# Share history across sessions: write after each command, re-read before prompt
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }history -a; history -r"

# Ctrl-P/N: history search by prefix (mirrors zsh bindkey behavior)
bind '"\C-p": history-search-backward'
bind '"\C-n": history-search-forward'

# ---------------------------------------------------------------------------
# Aliases (override Omarchy's eza aliases with user's preferred layout)
# ---------------------------------------------------------------------------
alias vi="nvim"
alias vim="nvim"
alias lg="lazygit"

alias ld="eza -lD"
alias lf="eza -lf --color=always | grep -v /"
alias lh="eza -dl .* --group-directories-first"
alias ls="eza -a --color=always --group-directories-first"
alias lt="eza -al --sort=modified"

# Reload .bashrc
ss() { source ~/.bashrc; }
