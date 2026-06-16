#!/usr/bin/env bash
# permission-policy.sh — matchers for the PreToolUse permission-policy.sh hook.
#                        Source this file; do not execute it directly.
#
# Public API (each prints a non-empty "ask" reason on match, empty otherwise):
#   check_bash <command>                 -- risky bash shapes
#   check_file_edit <path> <wt_root>     -- sensitive file edits
#   check_web_fetch <url>                -- exfil / suspect-host URLs

# --- check_bash -----------------------------------------------------------
# Inspect a bash command for risky shapes the static deny/ask lists miss:
# shell-expanded secret paths, rm -rf bypass forms, curl|sh, chained rm -rf,
# and base64/tar/gpg|curl exfil pipelines.
# Arguments: $1 command string
# Outputs:   a reason string on match; empty string otherwise
# Returns:   0 always
# shellcheck disable=SC2016  # intentional literal $HOME / ${HOME} matching
check_bash() {
  local cmd="$1"
  # Shell-expanded secret paths the tilde-prefix deny list misses.
  if [[ "$cmd" == *'$HOME/.ssh/'* ||
    "$cmd" == *'${HOME}/.ssh/'* ||
    "$cmd" == *'/Users/ben/.ssh/'* ||
    "$cmd" == *'$HOME/.aws/credentials'* ||
    "$cmd" == *'${HOME}/.aws/credentials'* ||
    "$cmd" == *'/Users/ben/.aws/credentials'* ||
    "$cmd" == *'$HOME/.claude/.credentials'* ||
    "$cmd" == *'${HOME}/.claude/.credentials'* ||
    "$cmd" == *'/Users/ben/.claude/.credentials'* ||
    "$cmd" == *'$HOME/.gnupg/'* ||
    "$cmd" == *'${HOME}/.gnupg/'* ||
    "$cmd" == *'/Users/ben/.gnupg/'* ]]; then
    printf 'Bash command references secret path via non-tilde form'
    return 0
  fi
  # Bypass attempts for `rm -rf` that evade the deny/ask pattern.
  # Detect leading whitespace AND prefixed command forms directly against $cmd.
  if [[ "$cmd" =~ ^[[:space:]]+rm[[:space:]]+-r[fF]?[[:space:]] ||
    "$cmd" =~ ^\\rm[[:space:]]+-r[fF]?[[:space:]] ||
    "$cmd" =~ ^command[[:space:]]+rm[[:space:]]+-r[fF]?[[:space:]] ||
    "$cmd" =~ ^builtin[[:space:]]+rm[[:space:]]+-r[fF]?[[:space:]] ||
    "$cmd" =~ ^\"rm\"[[:space:]]+-r[fF]?[[:space:]] ||
    "$cmd" =~ ^\'rm\'[[:space:]]+-r[fF]?[[:space:]] ]]; then
    printf 'Possible deny-list bypass for rm -rf'
    return 0
  fi
  # Curl/wget piped into a shell -- classic RCE-from-network shape.
  if [[ "$cmd" =~ (curl|wget)[^\|]*\|[[:space:]]*(bash|sh|zsh|ksh)([[:space:]]|$) ]]; then
    printf 'Piped/chained execution of fetched content'
    return 0
  fi
  # Semicolon- or &&-chained rm -rf hiding behind a benign-looking prefix.
  if [[ "$cmd" =~ (\;|&&)[[:space:]]*rm[[:space:]]+-r[fF]?[[:space:]] ]]; then
    printf 'Piped/chained execution of fetched content'
    return 0
  fi
  # base64|curl/wget or tar|curl/wget or gpg|curl -- classic exfil shapes.
  if [[ "$cmd" =~ (base64|tar|gpg)[^\|]*\|[^\|]*(curl|wget)[[:space:]] ]]; then
    printf 'Possible data exfiltration pipeline'
    return 0
  fi
  printf ''
}

# --- check_file_edit ------------------------------------------------------
# Flag edits to safety-critical live ~/.claude/ config outside the current
# worktree, or to shell-init / persistence files. Edits via the dotfiles
# source path (e.g. zsh/.zshrc inside the repo) do not match and stay silent.
# Arguments: $1 file path, $2 worktree root (optional)
# Outputs:   a reason string on match; empty string otherwise
# Returns:   0 always
check_file_edit() {
  local path="$1" wt_root="${2:-}"

  # Edits to live ~/.claude/ go through the symlink to the dotfiles source.
  # Flag them so the user routes the change through the dotfiles repo
  # (settings.base.json + claude-sync) rather than mutating live config in
  # ways that get clobbered on next regenerate, or bypass the worktree flow.
  # The dotfiles source path (/Users/ben/workspace/dotfiles/...) does not
  # match this prefix and is implicitly allowed.
  if [[ "$path" == /Users/ben/.claude/* ]]; then
    if [[ -n "$wt_root" && "$path" == "$wt_root"/* ]]; then
      :
    else
      printf 'Edit to live ~/.claude/ outside the dotfiles repo -- edit settings.base.json or stowed source instead'
      return 0
    fi
  fi

  # Shell init / persistence files via live paths. Edits via the dotfiles
  # source path (e.g., zsh/.zshrc inside the repo) don't match here and
  # stay silent naturally.
  if [[ "$path" == /Users/ben/.zshrc ||
    "$path" == /Users/ben/.zshenv ||
    "$path" == /Users/ben/.zprofile ||
    "$path" == /Users/ben/.zlogin ||
    "$path" == /Users/ben/.bashrc ||
    "$path" == /Users/ben/.bash_profile ||
    "$path" == /Users/ben/.profile ||
    "$path" == /Users/ben/.gitconfig ||
    "$path" == /Users/ben/Library/LaunchAgents/* ||
    "$path" == /Users/ben/.config/launchd/* ||
    "$path" == /etc/crontab ||
    "$path" == /var/spool/cron/* ]]; then
    if [[ -n "$wt_root" && "$path" == "$wt_root"/* ]]; then
      :
    else
      printf 'Shell init / persistence file edit'
      return 0
    fi
  fi

  printf ''
}

# --- check_web_fetch ------------------------------------------------------
# Flag a URL that matches exfil / suspect-host / local-path patterns:
# dynamic-DNS/paste/webhook hosts, oversized or base64-shaped query strings,
# or URLs that embed a local filesystem path / shell var.
# Arguments: $1 URL string
# Outputs:   a reason string on match; empty string otherwise
# Returns:   0 always
# shellcheck disable=SC2016  # intentional literal $HOME / ${HOME} matching
check_web_fetch() {
  local url="$1"
  local url_lc="${url,,}"

  # Suspect hosts: dynamic-DNS, paste, webhook receivers. Case-insensitive via lc copy.
  if [[ "$url_lc" =~ ^https?://([^/]*\.)?(requestbin\.com|webhook\.site|pipedream\.net|ngrok\.io|trycloudflare\.com)([/:?]|$) ]]; then
    printf 'Fetch to dynamic-DNS / paste / webhook host'
    return 0
  fi

  # Extract query string (everything after first `?`, strip fragment).
  local query=""
  if [[ "$url" == *\?* ]]; then
    query="${url#*\?}"
    query="${query%%#*}"
  fi
  if ((${#query} > 500)); then
    printf 'Fetch URL carries large query payload (possible exfil)'
    return 0
  fi
  if [[ "$query" =~ [A-Za-z0-9+/]{120,}={0,2} ]]; then
    printf 'Fetch URL carries large query payload (possible exfil)'
    return 0
  fi

  # URL references a local filesystem path or shell var (likely exfil bait).
  if [[ "$url" == *'/Users/ben/'* ||
    "$url" == *'$HOME/'* ||
    "$url" == *'${HOME}/'* ]]; then
    printf 'Fetch URL references local filesystem path'
    return 0
  fi

  printf ''
}
