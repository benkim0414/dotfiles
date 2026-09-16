#!/usr/bin/env bash
set -u

DOTFILES=$(cd "$(dirname "$0")/../../.." && pwd)
ZSHENV="$DOTFILES/zsh/.zshenv"

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

t_defaults_terminal_browser_to_30_fps() {
  local output
  output=$(env -u TERMINAL_BROWSER_FPS zsh -f -c "source '$ZSHENV'; print -- \$TERMINAL_BROWSER_FPS")
  if [[ "$output" == "30" ]]; then
    ok "defaults terminal-browser to 30 FPS"
  else
    bad "defaults terminal-browser to 30 FPS ($output)"
  fi
}

t_preserves_terminal_browser_fps_override() {
  local output
  output=$(TERMINAL_BROWSER_FPS=24 zsh -f -c "source '$ZSHENV'; print -- \$TERMINAL_BROWSER_FPS")
  if [[ "$output" == "24" ]]; then
    ok "preserves terminal-browser FPS override"
  else
    bad "preserves terminal-browser FPS override ($output)"
  fi
}

main() {
  t_defaults_terminal_browser_to_30_fps
  t_preserves_terminal_browser_fps_override
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}

main "$@"
