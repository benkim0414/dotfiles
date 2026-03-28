#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/lib/portability.sh"

# Catppuccin Mocha — 24-bit ANSI colors (hex values from starship.toml)
RESET='\033[0m'
MAUVE='\033[38;2;203;166;247m'   # #cba6f7
BLUE='\033[38;2;137;180;250m'    # #89b4fa
GREEN='\033[38;2;166;227;161m'   # #a6e3a1
YELLOW='\033[38;2;249;226;175m'  # #f9e2af
RED='\033[38;2;243;139;168m'     # #f38ba8
TEAL='\033[38;2;148;226;213m'    # #94e2d5
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

# Color thresholds: >=90 red, >=70 yellow, else green/teal.
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
  mkdir -p "$cache_dir" 2>/dev/null || true
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

# Build output — model and context are always shown.
out="${MAUVE}${model}${RESET}"
if [[ -n "$cwd" ]]; then
  display_cwd="${cwd/#$HOME/\~}"
  out+="${sep}${BLUE}${display_cwd}${RESET}"
fi
if [[ -n "$git_branch" ]]; then
  out+="${sep}${RED}${git_branch}${RESET}"
fi
out+="${sep}${ctx_color}ctx ${ctx_pct}%${RESET}"

# Rate limits — only when non-zero (Pro/Max subscribers).
for pair in "5h:$rate_5h" "7d:$rate_7d"; do
  label="${pair%%:*}"
  pct="${pair##*:}"
  if (( pct > 0 )); then
    if (( pct >= 90 )); then
      rc="$RED"
    elif (( pct >= 70 )); then
      rc="$YELLOW"
    else
      rc="$TEAL"
    fi
    out+="${sep}${rc}${label} ${pct}%${RESET}"
  fi
done

printf '%b\n' "$out"
