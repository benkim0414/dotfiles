#!/usr/bin/env bash
# Notification hook: alert the user via Ghostty OSC 777 desktop notification
# and tmux bell when Claude Code needs attention.
# Runs async (non-blocking) -- must never slow down Claude Code.
set -euo pipefail

INPUT=$(cat)
IFS=$'\t' read -r NTYPE MESSAGE SESSION_ID CWD <<< "$(
  printf '%s' "$INPUT" | jq -r '[
    (.notification_type // ""),
    (.message // ""),
    (.session_id // ""),
    (.cwd // "")
  ] | @tsv'
)"

# Only notify for types where Claude is blocked waiting for the user.
case "$NTYPE" in
  permission_prompt|idle_prompt|elicitation_dialog) ;;
  *) exit 0 ;;
esac

# --- Deduplication: 10-second cooldown per session ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
if [[ -n "$SESSION_ID" ]]; then
  COOLDOWN_FILE="${CACHE_DIR}/notify-${SESSION_ID}"
  NOW=$(date +%s)
  if [[ -f "$COOLDOWN_FILE" ]]; then
    LAST=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
    if (( NOW - LAST < 10 )); then
      exit 0
    fi
  fi
  printf '%s' "$NOW" > "$COOLDOWN_FILE" 2>/dev/null || true
fi

# --- Resolve tmux pane context ---
PANE_LABEL=""
PANE_TTY=""
if [[ -n "${TMUX_PANE:-}" ]]; then
  PANE_LABEL=$(tmux display-message -t "$TMUX_PANE" \
    -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)
  PANE_TTY=$(tmux display-message -t "$TMUX_PANE" \
    -p '#{pane_tty}' 2>/dev/null || true)
fi

# Short project name from cwd.
PROJECT=""
if [[ -n "$CWD" ]]; then
  PROJECT=$(basename "$CWD")
fi

# --- Write attention marker for tmux-attention switcher ---
if [[ -n "${TMUX_PANE:-}" ]]; then
  ATTN_DIR="${CACHE_DIR}/attention"
  mkdir -p "$ATTN_DIR" 2>/dev/null || true
  printf '%s\n' \
    "pane_id=${TMUX_PANE}" \
    "pane_label=${PANE_LABEL}" \
    "notification_type=${NTYPE}" \
    "project=${PROJECT}" \
    "cwd=${CWD}" \
    "timestamp=$(date +%s)" \
    > "${ATTN_DIR}/${TMUX_PANE}" 2>/dev/null || true
fi

# --- Build notification title and body ---
TITLE="Claude Code"
case "$NTYPE" in
  permission_prompt)  TITLE="Approval Needed" ;;
  idle_prompt)        TITLE="Task Complete" ;;
  elicitation_dialog) TITLE="Input Needed" ;;
esac

BODY=""
if [[ -n "$PROJECT" && -n "$PANE_LABEL" ]]; then
  BODY="${PROJECT} (${PANE_LABEL})"
elif [[ -n "$PROJECT" ]]; then
  BODY="$PROJECT"
elif [[ -n "$PANE_LABEL" ]]; then
  BODY="$PANE_LABEL"
fi
# Strip control characters (BEL, ESC, etc.) from message to prevent
# premature termination of the OSC 777 / DCS passthrough sequences.
MESSAGE=$(printf '%s' "$MESSAGE" | tr -d '\000-\037\177')
if [[ -n "$MESSAGE" ]]; then
  BODY="${BODY:+${BODY} - }${MESSAGE}"
fi

# --- Send Ghostty desktop notification via OSC 777 ---
# shellcheck disable=SC1003  # ShellCheck misreads \a\e\\ as a quote escape; \a is BEL in printf
send_osc777() {
  local title="$1" body="$2" target="$3"
  if [[ -n "${TMUX:-}" ]]; then
    # Wrap in DCS passthrough so tmux forwards to Ghostty.
    printf '\ePtmux;\e\e]777;notify;%s;%s\a\e\\' "$title" "$body" > "$target"
  else
    # Direct Ghostty (no tmux).
    printf '\e]777;notify;%s;%s\a' "$title" "$body" > "$target"
  fi
}

if [[ -n "$PANE_TTY" && -w "$PANE_TTY" ]]; then
  send_osc777 "$TITLE" "$BODY" "$PANE_TTY"
elif [[ -z "${TMUX:-}" ]]; then
  # Not in tmux -- write to current tty.
  TTY=$(tty 2>/dev/null || true)
  if [[ -n "$TTY" && -w "$TTY" ]]; then
    send_osc777 "$TITLE" "$BODY" "$TTY"
  fi
fi

# --- Trigger tmux bell ---
# BEL is handled natively by tmux (no passthrough needed).
# Lights up the bell icon in the Catppuccin status bar for this window.
if [[ -n "$PANE_TTY" && -w "$PANE_TTY" ]]; then
  printf '\a' > "$PANE_TTY"
fi

exit 0
