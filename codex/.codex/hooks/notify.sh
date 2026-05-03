#!/usr/bin/env bash
# Notification script for Codex CLI.
# Called by the `notify` config key in config.toml.
# Sends Ghostty OSC 777 desktop notification + tmux bell.
#
# Codex passes a JSON payload on stdin with notification details.
set -euo pipefail

: "${EPOCHSECONDS:=$(date +%s)}"

INPUT=$(cat)

# Extract fields from Codex notification payload.
IFS=$'\t' read -r MESSAGE SESSION_ID CWD NTYPE <<< "$(
  printf '%s' "$INPUT" | jq -r '[
    (.message // ""),
    (.session_id // ""),
    (.cwd // ""),
    (.notification_type // .type // "idle_prompt")
  ] | @tsv'
)"

# --- Shared state ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex"
[[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- Resolve tmux pane context ---
PANE_LABEL=""
PANE_TTY=""
if [[ -n "${TMUX_PANE:-}" ]]; then
  IFS=$'\t' read -r PANE_LABEL PANE_TTY <<< "$(
    tmux display-message -t "$TMUX_PANE" \
      -p '#{session_name}:#{window_index}.#{pane_index}'$'\t''#{pane_tty}' 2>/dev/null || true
  )"
fi

# Short project name from cwd.
PROJECT=""
if [[ -n "$CWD" ]]; then
  PROJECT=$(basename "$CWD")
fi

# --- Write attention marker for tmux status integration ---
if [[ -n "${TMUX_PANE:-}" ]]; then
  ATTN_DIR="${CACHE_DIR}/attention"
  [[ -d "$ATTN_DIR" ]] || mkdir -p "$ATTN_DIR" 2>/dev/null || true
  MARKER_TMP=$(mktemp "${ATTN_DIR}/.tmp.XXXXXX" 2>/dev/null) || true
  if [[ -n "${MARKER_TMP:-}" ]]; then
    printf '%s\n' \
      "pane_id=${TMUX_PANE}" \
      "pane_label=${PANE_LABEL}" \
      "tool=codex" \
      "notification_type=${NTYPE}" \
      "project=${PROJECT}" \
      "cwd=${CWD}" \
      "timestamp=${EPOCHSECONDS}" \
      > "$MARKER_TMP" 2>/dev/null || true
    mv -f "$MARKER_TMP" "${ATTN_DIR}/${TMUX_PANE}" 2>/dev/null || true
  fi
fi

# --- Deduplication: 10-second cooldown per session ---
if [[ -n "$SESSION_ID" ]]; then
  COOLDOWN_FILE="${CACHE_DIR}/notify-${SESSION_ID}"
  NOW=$EPOCHSECONDS
  if [[ -f "$COOLDOWN_FILE" ]]; then
    LAST=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
    if (( NOW - LAST < 10 )); then
      exit 0
    fi
  fi
  printf '%s' "$NOW" > "$COOLDOWN_FILE" 2>/dev/null || true
fi

# --- Build notification body ---
TITLE="Codex"
# Strip control characters from message.
MESSAGE=$(printf '%s' "$MESSAGE" | tr -d '\000-\037\177')

BODY=""
if [[ -n "$PROJECT" && -n "$PANE_LABEL" ]]; then
  BODY="${PROJECT} (${PANE_LABEL})"
elif [[ -n "$PROJECT" ]]; then
  BODY="$PROJECT"
elif [[ -n "$PANE_LABEL" ]]; then
  BODY="$PANE_LABEL"
fi
if [[ -n "$MESSAGE" ]]; then
  BODY="${BODY:+${BODY} - }${MESSAGE}"
fi

# --- Send Ghostty desktop notification via OSC 777 ---
# shellcheck disable=SC1003
send_osc777() {
  local title="$1" body="$2" target="$3"
  if [[ -n "${TMUX:-}" ]]; then
    printf '\ePtmux;\e\e]777;notify;%s;%s\a\e\\' "$title" "$body" > "$target"
  else
    printf '\e]777;notify;%s;%s\a' "$title" "$body" > "$target"
  fi
}

if [[ -n "$PANE_TTY" && -w "$PANE_TTY" ]]; then
  send_osc777 "$TITLE" "$BODY" "$PANE_TTY"
elif [[ -z "${TMUX:-}" ]]; then
  TTY=$(tty 2>/dev/null || true)
  if [[ -n "$TTY" && -w "$TTY" ]]; then
    send_osc777 "$TITLE" "$BODY" "$TTY"
  fi
fi

# --- Trigger tmux bell ---
if [[ -n "$PANE_TTY" && -w "$PANE_TTY" ]]; then
  printf '\a' > "$PANE_TTY"
fi

exit 0
