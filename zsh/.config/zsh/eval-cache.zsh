_eval_cache_warn() {
  local name="$1"
  local install_hint="$2"
  print -u2 -- "zsh: ${name} init unavailable; install with: ${install_hint}"
}

_eval_cache_valid_zsh_file() {
  local file="$1"
  [[ -s "$file" ]] || return 1
  if command grep -q \
    -e '^The following packages have to be installed:' \
    -e '^ \* Waiting in queue' \
    -e '^ \* Waiting for authentication' \
    -e '^ \* Downloading packages' \
    -e '^ \* Installing packages' \
    "$file" 2>/dev/null; then
    return 1
  fi
  zsh -n "$file" >/dev/null 2>&1
}

_eval_cache() {
  local name="$1"
  local install_hint="$2"
  shift 2

  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/eval-cache-${name}.zsh"
  local cache_dir="${cache:h}"
  local bin_path
  local temp
  local needs_refresh=0

  bin_path="$(command -v "$1" 2>/dev/null)"
  if [[ -z "$bin_path" ]]; then
    _eval_cache_warn "$name" "$install_hint"
    return 0
  fi

  if [[ ! -s "$cache" || "$bin_path" -nt "$cache" ]]; then
    needs_refresh=1
  elif ! _eval_cache_valid_zsh_file "$cache"; then
    needs_refresh=1
  fi

  if (( needs_refresh )); then
    mkdir -p "$cache_dir"
    temp="${cache}.${$}.tmp"
    if "$@" >| "$temp" && _eval_cache_valid_zsh_file "$temp"; then
      command mv -f "$temp" "$cache"
    else
      command rm -f "$temp"
      if ! _eval_cache_valid_zsh_file "$cache"; then
        command rm -f "$cache"
        _eval_cache_warn "$name" "$install_hint"
        return 0
      fi
    fi
  fi

  if _eval_cache_valid_zsh_file "$cache"; then
    source "$cache"
  else
    command rm -f "$cache"
    _eval_cache_warn "$name" "$install_hint"
  fi
}
