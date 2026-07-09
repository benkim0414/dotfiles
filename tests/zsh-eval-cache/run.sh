#!/usr/bin/env bash
set -u

DOTFILES=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$DOTFILES/zsh/.config/zsh/eval-cache.zsh"

PASS=0
FAIL=0
TMP=""

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

cleanup() {
  if [[ -n "$TMP" && -d "$TMP" ]]; then
    rm -rf "$TMP"
  fi
}

setup_case() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/bin" "$TMP/home/.config/zsh" "$TMP/cache"
  cp "$HELPER" "$TMP/home/.config/zsh/eval-cache.zsh"
}

write_fake() {
  local name="$1"
  local body="$2"
  printf '%s\n' '#!/usr/bin/env bash' "$body" >"$TMP/bin/$name"
  chmod +x "$TMP/bin/$name"
}

run_zsh() {
  local script="$1"
  HOME="$TMP/home" \
  XDG_CONFIG_HOME="$TMP/home/.config" \
  XDG_CACHE_HOME="$TMP/cache" \
  PATH="$TMP/bin:/usr/bin:/bin" \
    zsh -f -c "$script"
}

t_valid_output_is_cached_and_sourced() {
  setup_case
  write_fake fakefzf 'printf "%s\\n" "export FZF_TEST_LOADED=1"'

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache fakefzf "sudo dnf install fzf" fakefzf; print -- "$FZF_TEST_LOADED"' 2>&1)
  if [[ "$output" == "1" && -s "$TMP/cache/zsh/eval-cache-fakefzf.zsh" ]]; then
    ok "valid generated output is cached and sourced"
  else
    bad "valid generated output is cached and sourced ($output)"
  fi
}

t_packagekit_output_is_rejected() {
  setup_case
  write_fake fakefzf 'cat <<'"'"'OUT'"'"'
The following packages have to be installed:
 fzf_0.73.1-1.fc44.x86_64  A command-line fuzzy finder written in Go
OUT'

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache fakefzf "sudo dnf install fzf" fakefzf; print -- "${FZF_TEST_LOADED:-unset}"' 2>&1)
  if [[ "$output" == *"zsh: fakefzf init unavailable; install with: sudo dnf install fzf"* ]] \
    && [[ "$output" == *"unset"* ]] \
    && [[ ! -s "$TMP/cache/zsh/eval-cache-fakefzf.zsh" ]]; then
    ok "PackageKit command-not-found output is rejected"
  else
    bad "PackageKit command-not-found output is rejected ($output)"
  fi
}

t_missing_command_warns_and_skips_stale_cache() {
  setup_case
  mkdir -p "$TMP/cache/zsh"
  printf '%s\n' 'export STALE_CACHE_SOURCED=1' >"$TMP/cache/zsh/eval-cache-missingtool.zsh"

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache missingtool "sudo dnf install missingtool" missingtool; print -- "${STALE_CACHE_SOURCED:-unset}"' 2>&1)
  if [[ "$output" == *"zsh: missingtool init unavailable; install with: sudo dnf install missingtool"* ]] \
    && [[ "$output" == *"unset"* ]]; then
    ok "missing command warns and does not source stale cache"
  else
    bad "missing command warns and does not source stale cache ($output)"
  fi
}

t_invalid_existing_cache_is_not_sourced() {
  setup_case
  mkdir -p "$TMP/cache/zsh"
  printf '%s\n' 'The following packages have to be installed:' >"$TMP/cache/zsh/eval-cache-fakezoxide.zsh"

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache fakezoxide "sudo dnf install zoxide" fakezoxide; print -- "${ZOXIDE_TEST_LOADED:-unset}"' 2>&1)
  if [[ "$output" == *"zsh: fakezoxide init unavailable; install with: sudo dnf install zoxide"* ]] \
    && [[ "$output" == *"unset"* ]]; then
    ok "invalid existing cache is not sourced"
  else
    bad "invalid existing cache is not sourced ($output)"
  fi
}

t_command_failure_keeps_valid_existing_cache() {
  setup_case
  write_fake flakytool 'exit 42'
  mkdir -p "$TMP/cache/zsh"
  printf '%s\n' 'export FLAKY_CACHE_SOURCED=1' >"$TMP/cache/zsh/eval-cache-flakytool.zsh"

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache flakytool "sudo dnf install flakytool" flakytool; print -- "${FLAKY_CACHE_SOURCED:-unset}"' 2>&1)
  if [[ "$output" == *"1"* ]] && [[ "$output" != *"zsh: flakytool init unavailable"* ]]; then
    ok "command failure keeps valid existing cache"
  else
    bad "command failure keeps valid existing cache ($output)"
  fi
}

main() {
  trap cleanup EXIT
  t_valid_output_is_cached_and_sourced
  cleanup
  t_packagekit_output_is_rejected
  cleanup
  t_missing_command_warns_and_skips_stale_cache
  cleanup
  t_invalid_existing_cache_is_not_sourced
  cleanup
  t_command_failure_keeps_valid_existing_cache
  cleanup

  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}

main "$@"
