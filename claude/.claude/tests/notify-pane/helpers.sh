# helpers.sh — shared setup for notify-pane tests.
# Sourced by each case. Provides mock tmux/ps on PATH + assert helpers.
set -uo pipefail

: "${LIB:?LIB must be set by run.sh}"
: "${HOOK:?HOOK must be set by run.sh}"

# Create an isolated temp dir and a mock-bin on PATH.
# Sets globals: TMPROOT, MOCKBIN. Mock ps/tmux read fixture files named by
# the MOCK_PS_FILE / MOCK_PANES_FILE env vars (empty output if unset).
setup_mocks() {
  TMPROOT="$(mktemp -d)"
  MOCKBIN="$TMPROOT/bin"
  mkdir -p "$MOCKBIN"

  cat > "$MOCKBIN/ps" <<'EOF'
#!/usr/bin/env bash
# Mock ps: ignore args, emit the pid/ppid fixture.
cat "${MOCK_PS_FILE:-/dev/null}" 2>/dev/null || true
EOF

  cat > "$MOCKBIN/tmux" <<'EOF'
#!/usr/bin/env bash
# Mock tmux: list-panes emits the pane fixture; display-message emits an
# empty (tab-separated) label/tty so the hook's marker block still runs.
case "${1:-}" in
  list-panes)      cat "${MOCK_PANES_FILE:-/dev/null}" 2>/dev/null || true ;;
  display-message) printf '\t' ;;
  *)               : ;;
esac
EOF

  chmod +x "$MOCKBIN/ps" "$MOCKBIN/tmux"
  export PATH="$MOCKBIN:$PATH"
}

teardown_mocks() { [[ -n "${TMPROOT:-}" ]] && rm -rf "$TMPROOT"; }

assert_eq() {
  local got="$1" want="$2" msg="${3:-assert_eq}"
  if [[ "$got" != "$want" ]]; then
    printf '%s FAILED\n  got:  %q\n  want: %q\n' "$msg" "$got" "$want" >&2
    return 1
  fi
}

assert_file() {
  [[ -f "$1" ]] || { printf 'assert_file FAILED: missing %s\n' "$1" >&2; return 1; }
}

assert_grep() {
  grep -q "$1" "$2" || { printf 'assert_grep FAILED: /%s/ not in %s\n' "$1" "$2" >&2; return 1; }
}
