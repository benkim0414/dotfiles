#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

stub_bin="$TMPDIR_ROOT/bin"
mkdir -p "$stub_bin"

# The single-quoted strings below are the generated tmux stub script.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  display-message)' \
  '    if [[ "$*" == *"#{session_name}:#{window_index}.#{pane_index}"* ]]; then' \
  '      printf "session:1.2\t/dev/null\n"' \
  '    elif [[ "$*" == *"#{pane_id}"* ]]; then' \
  '      printf "%%7\n"' \
  '    fi' \
  '    ;;' \
  '  switch-client|select-pane)' \
  '    ;;' \
  'esac' \
  > "$stub_bin/tmux"
chmod +x "$stub_bin/tmux"

assert_file_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -qxF "$expected" "$file"; then
    printf 'not ok - expected %s in %s\n' "$expected" "$file" >&2
    printf '%s\n' "--- $file ---" >&2
    cat "$file" >&2
    return 1
  fi
}

assert_equals() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\nexpected: %s\nactual: %s\n' "$name" "$expected" "$actual" >&2
    return 1
  fi
  printf 'ok - %s\n' "$name"
}

cache="$TMPDIR_ROOT/cache"
payload='{"message":"done","session_id":"session-1","cwd":"/tmp/example-project"}'
printf '%s' "$payload" | env \
  PATH="$stub_bin:$PATH" \
  XDG_CACHE_HOME="$cache" \
  TMUX=/tmp/tmux-1000/default,1,0 \
  TMUX_PANE=%7 \
  bash "$REPO_ROOT/codex/.codex/hooks/notify.sh"

codex_marker="$cache/codex/attention/%7"
assert_file_contains "$codex_marker" "tool=codex"
assert_file_contains "$codex_marker" "notification_type=idle_prompt"
assert_file_contains "$codex_marker" "project=example-project"
printf 'ok - codex notify writes complete marker\n'

now=$(date +%s)
mkdir -p "$cache/claude/attention" "$cache/codex/attention"
printf 'pane_id=%%1\ntimestamp=%s\nnotification_type=permission_prompt\n' "$now" > "$cache/claude/attention/%1"
printf 'pane_id=%%2\ntimestamp=%s\nnotification_type=idle_prompt\n' "$now" > "$cache/codex/attention/%2"
badge=$(env PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache" bash "$REPO_ROOT/bin/.local/bin/tmux-attention-badge")
assert_equals "badge counts claude and codex markers" " 󰂚 3 waiting" "$badge"

old=$((now - 301))
printf 'pane_id=%%3\ntimestamp=%s\nnotification_type=idle_prompt\n' "$old" > "$cache/codex/attention/%3"
badge=$(env PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache" bash "$REPO_ROOT/bin/.local/bin/tmux-attention-badge")
assert_equals "badge removes stale markers" " 󰂚 3 waiting" "$badge"
if [[ -e "$cache/codex/attention/%3" ]]; then
  printf 'not ok - stale marker still exists\n' >&2
  exit 1
fi
printf 'ok - stale marker removed\n'

printf 'pane_id=%%7\ntimestamp=%s\nnotification_type=idle_prompt\n' "$now" > "$cache/claude/attention/%7"
printf 'pane_id=%%7\ntimestamp=%s\nnotification_type=idle_prompt\n' "$now" > "$cache/codex/attention/%7"
env PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache" bash "$REPO_ROOT/bin/.local/bin/tmux-attention" --clear-focused
if [[ -e "$cache/claude/attention/%7" || -e "$cache/codex/attention/%7" ]]; then
  printf 'not ok - clear-focused did not remove both markers\n' >&2
  exit 1
fi
printf 'ok - clear-focused removes claude and codex markers\n'

rm -f "$cache/claude/attention/"%* "$cache/codex/attention/"%*
printf 'pane_id=%%8\ntimestamp=%s\nproject=legacy-codex\n' "$now" > "$cache/codex/attention/%8"
env PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache" bash "$REPO_ROOT/bin/.local/bin/tmux-attention"
if [[ -e "$cache/codex/attention/%8" ]]; then
  printf 'not ok - legacy codex marker was not handled\n' >&2
  exit 1
fi
printf 'ok - legacy codex marker without optional fields is handled\n'
