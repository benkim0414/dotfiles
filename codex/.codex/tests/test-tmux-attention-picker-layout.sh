#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

stub_bin="$TMPDIR_ROOT/bin"
mkdir -p "$stub_bin"

# The single-quoted strings below are generated stub scripts.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  display-message)' \
  '    if [[ "$*" == *"#{window_width} #{window_height}"* ]]; then' \
  '      printf "%s\n" "${TMUX_TEST_SIZE:-}"' \
  '    elif [[ "$*" == *"#{session_name}"* ]]; then' \
  '      printf "session\n"' \
  '    fi' \
  '    ;;' \
  '  list-panes)' \
  '    printf "%%1\tsession\t1\t1\t100\t%s\tCodex One\n" "$TMUX_TEST_PATH_ONE"' \
  '    printf "%%2\tsession\t1\t2\t200\t%s\tCodex Two\n" "$TMUX_TEST_PATH_TWO"' \
  '    ;;' \
  '  capture-pane)' \
  '    printf "preview\n"' \
  '    ;;' \
  '  switch-client|select-pane)' \
  '    ;;' \
  'esac' \
  > "$stub_bin/tmux"
chmod +x "$stub_bin/tmux"

# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "${1:-}" == "-x" && "${2:-}" == "codex" ]]; then' \
  '  printf "300\n301\n"' \
  '  exit 0' \
  'fi' \
  'exit 1' \
  > "$stub_bin/pgrep"
chmod +x "$stub_bin/pgrep"

# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "$*" == "-eo pid=,ppid=" ]]; then' \
  '  printf "300 100\n301 200\n100 1\n200 1\n"' \
  'fi' \
  > "$stub_bin/ps"
chmod +x "$stub_bin/ps"

# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$@" > "$FZF_ARGS_FILE"' \
  'first=""' \
  'IFS= read -r first || true' \
  'printf "%s\n" "$first"' \
  > "$stub_bin/fzf"
chmod +x "$stub_bin/fzf"

assert_layout() {
  local name="$1"
  local size="$2"
  local expected="$3"
  local run_dir args_file

  run_dir="$TMPDIR_ROOT/$name"
  args_file="$run_dir/fzf-args"
  mkdir -p "$run_dir/path-one" "$run_dir/path-two"

  env \
    PATH="$stub_bin:$PATH" \
    XDG_CACHE_HOME="$run_dir/cache" \
    FZF_ARGS_FILE="$args_file" \
    TMUX_TEST_SIZE="$size" \
    TMUX_TEST_PATH_ONE="$run_dir/path-one" \
    TMUX_TEST_PATH_TWO="$run_dir/path-two" \
    bash "$REPO_ROOT/bin/.local/bin/tmux-attention-picker"

  if ! grep -qxF -- "--preview-window=$expected" "$args_file"; then
    printf 'not ok - %s\nexpected: --preview-window=%s\n' "$name" "$expected" >&2
    printf '%s\n' "--- fzf args ---" >&2
    cat "$args_file" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_layout "narrow tall uses vertical preview" "119 40" "down,50%,border-top,wrap,follow"
assert_layout "flip column boundary stays horizontal" "120 40" "right,50%,border-left,wrap,follow"
assert_layout "narrow short stays horizontal" "119 39" "right,50%,border-left,wrap,follow"
assert_layout "bad tmux size falls back horizontal" "not-a-size" "right,50%,border-left,wrap,follow"
