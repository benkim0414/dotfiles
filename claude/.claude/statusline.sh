#!/usr/bin/env bash
set -euo pipefail

# Inline portability helpers (avoids readlink/source subprocess per render).
: "${EPOCHSECONDS:=$(date +%s)}"
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# Catppuccin Mocha — 24-bit ANSI colors (hex values from starship.toml)
RESET='\033[0m'
MAUVE='\033[38;2;203;166;247m'   # #cba6f7
BLUE='\033[38;2;137;180;250m'    # #89b4fa
GREEN='\033[38;2;166;227;161m'   # #a6e3a1
YELLOW='\033[38;2;249;226;175m'  # #f9e2af
RED='\033[38;2;243;139;168m'     # #f38ba8
OVERLAY='\033[38;2;108;112;134m' # #6c7086

# Read stdin once; parse all fields in a single jq invocation (tab-separated).
json=$(cat)
IFS=$'\t' read -r model ctx_pct rate_5h rate_7d cwd <<< "$(
  printf '%s' "$json" | jq -r '[
    (.model.display_name // "unknown" | ltrimstr("Claude ") | ascii_downcase),
    (.context_window.used_percentage // 0 | floor | tostring),
    (.rate_limits.five_hour.used_percentage // 0 | floor | tostring),
    (.rate_limits.seven_day.used_percentage // 0 | floor | tostring),
    (.cwd // "")
  ] | @tsv'
)"

# Color thresholds: >=90 red, >=70 yellow, else green.
if (( ctx_pct >= 90 )); then
  ctx_color="$RED"
elif (( ctx_pct >= 70 )); then
  ctx_color="$YELLOW"
else
  ctx_color="$GREEN"
fi

# Git branch — cached per working directory (5-second TTL).
git_branch=""
if [[ -n "$cwd" ]]; then
  cwd_key="${cwd//[^a-zA-Z0-9_]/_}_${#cwd}"
  cache_dir="${XDG_RUNTIME_DIR:-$HOME/.cache/claude}"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir" 2>/dev/null || true
  git_cache="${cache_dir}/statusline-git-${cwd_key}"
  cache_age=999
  if [[ -f "$git_cache" ]]; then
    cache_age=$(( EPOCHSECONDS - $(file_mtime "$git_cache") ))
  fi
  if (( cache_age > 5 )); then
    git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    printf '%s' "$git_branch" > "$git_cache" 2>/dev/null || true
  else
    git_branch=$(cat "$git_cache" 2>/dev/null || true)
  fi
fi

# Separator.
sep="${OVERLAY} │ ${RESET}"

# Visible length — strip ANSI escapes and count characters.
visible_len() {
  local stripped
  stripped=$(printf '%b' "$1" | sed $'s/\033\\[[0-9;]*m//g' | tr -d '\n')
  printf '%d' "${#stripped}"
}

# Line 1 (identity): model, directory, git branch.
line_id="${MAUVE}${model}${RESET}"
if [[ -n "$cwd" ]]; then
  # Fish-style path: abbreviate every component except the last.
  # Inline abbreviation avoids subshell forks per path component.
  tilde_cwd="${cwd/#$HOME/\~}"
  IFS='/' read -ra _parts <<< "$tilde_cwd"
  _n="${#_parts[@]}"
  display_cwd=""
  for (( _i=0; _i<_n; _i++ )); do
    _p="${_parts[$_i]}"
    if (( _i == _n - 1 )); then
      display_cwd+="$_p"
    elif [[ -z "$_p" ]]; then
      display_cwd+="/"
    elif [[ "$_p" == ".." ]]; then
      display_cwd+="../"
    elif [[ "$_p" == .* ]]; then
      display_cwd+=".${_p:1:1}/"
    else
      display_cwd+="${_p:0:1}/"
    fi
  done
  unset _parts _n _i _p
  line_id+="${sep}${BLUE}${display_cwd}${RESET}"
fi
if [[ -n "$git_branch" ]]; then
  line_id+="${sep}${RED}${git_branch}${RESET}"
fi

# Line 2 (metrics): context %, rate limits.
line_metrics="${ctx_color}ctx ${ctx_pct}%${RESET}"
for pair in "5h:$rate_5h" "7d:$rate_7d"; do
  label="${pair%%:*}"
  pct="${pair##*:}"
  if (( pct > 0 )); then
    if (( pct >= 90 )); then
      rc="$RED"
    elif (( pct >= 70 )); then
      rc="$YELLOW"
    else
      rc="$GREEN"
    fi
    line_metrics+="${sep}${rc}${label} ${pct}%${RESET}"
  fi
done

# Emit one line if it fits terminal width, two lines otherwise.
combined="${line_id}${sep}${line_metrics}"
cols=$(tput cols 2>/dev/null) || cols=80
(( cols > 0 )) || cols=80
if (( $(visible_len "$combined") <= cols )); then
  printf '%b\n' "$combined"
else
  printf '%b\n%b\n' "$line_id" "$line_metrics"
fi
