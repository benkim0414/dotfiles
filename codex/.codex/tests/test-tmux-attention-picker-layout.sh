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
  '    printf "%%1\tsession\t1\t1\t100\t%s\t%s\n" "$TMUX_TEST_PATH_ONE" "${TMUX_TEST_TITLE_ONE:-Codex One}"' \
  '    printf "%%2\tsession\t1\t2\t200\t%s\t%s\n" "$TMUX_TEST_PATH_TWO" "${TMUX_TEST_TITLE_TWO:-Codex Two}"' \
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
  'input=$(cat)' \
  'if [[ -n "${FZF_INPUT_FILE:-}" ]]; then' \
  '  printf "%s\n" "$input" > "$FZF_INPUT_FILE"' \
  'fi' \
  'first="${input%%$'\''\n'\''*}"' \
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

assert_codex_action_required_title() {
  local name="codex action-required title maps to status icon"
  local run_dir args_file input_file

  run_dir="$TMPDIR_ROOT/codex-action-required-title"
  args_file="$run_dir/fzf-args"
  input_file="$run_dir/fzf-input"
  mkdir -p "$run_dir/dotfiles" "$run_dir/other"

  env \
    PATH="$stub_bin:$PATH" \
    XDG_CACHE_HOME="$run_dir/cache" \
    FZF_ARGS_FILE="$args_file" \
    FZF_INPUT_FILE="$input_file" \
    TMUX_TEST_SIZE="120 40" \
    TMUX_TEST_PATH_ONE="$run_dir/dotfiles" \
    TMUX_TEST_PATH_TWO="$run_dir/other" \
    TMUX_TEST_TITLE_ONE="[!] Action Required | dotfiles" \
    TMUX_TEST_TITLE_TWO="Codex Two" \
    bash "$REPO_ROOT/bin/.local/bin/tmux-attention-picker"

  if ! grep -qF "󰂞" "$input_file"; then
    printf 'not ok - %s\nmissing action-required status icon\n' "$name" >&2
    cat "$input_file" >&2
    return 1
  fi
  if grep -qF "Action Required |" "$input_file"; then
    printf 'not ok - %s\nstatus title leaked into picker label\n' "$name" >&2
    cat "$input_file" >&2
    return 1
  fi
  if ! grep -qF "dotfiles" "$input_file"; then
    printf 'not ok - %s\nmissing normalized project label\n' "$name" >&2
    cat "$input_file" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_codex_spinner_title() {
  local name="codex spinner title strips loading glyph"
  local run_dir args_file input_file

  run_dir="$TMPDIR_ROOT/codex-spinner-title"
  args_file="$run_dir/fzf-args"
  input_file="$run_dir/fzf-input"
  mkdir -p "$run_dir/dotfiles" "$run_dir/other"

  env \
    PATH="$stub_bin:$PATH" \
    XDG_CACHE_HOME="$run_dir/cache" \
    FZF_ARGS_FILE="$args_file" \
    FZF_INPUT_FILE="$input_file" \
    TMUX_TEST_SIZE="120 40" \
    TMUX_TEST_PATH_ONE="$run_dir/dotfiles" \
    TMUX_TEST_PATH_TWO="$run_dir/other" \
    TMUX_TEST_TITLE_ONE="⠼ dotfiles" \
    TMUX_TEST_TITLE_TWO="Codex Two" \
    bash "$REPO_ROOT/bin/.local/bin/tmux-attention-picker"

  if grep -qF "⠼" "$input_file"; then
    printf 'not ok - %s\nspinner glyph leaked into picker label\n' "$name" >&2
    cat "$input_file" >&2
    return 1
  fi
  if ! grep -qF "dotfiles" "$input_file"; then
    printf 'not ok - %s\nmissing normalized project label\n' "$name" >&2
    cat "$input_file" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_layout "narrow tall uses vertical preview" "119 40" "down,50%,border-top,wrap,follow"
assert_layout "flip column boundary stays horizontal" "120 40" "right,50%,border-left,wrap,follow"
assert_layout "narrow short stays horizontal" "119 39" "right,50%,border-left,wrap,follow"
assert_layout "bad tmux size falls back horizontal" "not-a-size" "right,50%,border-left,wrap,follow"
assert_codex_action_required_title
assert_codex_spinner_title
