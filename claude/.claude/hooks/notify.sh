#!/usr/bin/env bash
# Attention hook: alert the user via Ghostty OSC 777 desktop notification
# and tmux bell when Claude Code needs attention.
#
# Called from two hook contexts:
#   Notification   -- permission_prompt, idle_prompt, elicitation_dialog
#   PreToolUse     -- AskUserQuestion, ExitPlanMode
#
# The script detects its context via hook_event_name in the JSON payload.
# Runs async (non-blocking) -- must never slow down Claude Code.

# _attn_* globals are set by resolve_attention() in the sourced lib.
# shellcheck disable=SC2154
set -euo pipefail

: "${EPOCHSECONDS:=$(date +%s)}"

INPUT=$(cat)

# Single jq call extracts all fields for both hook contexts (PreToolUse and Notification).
IFS=$'\t' read -r HOOK_EVENT TOOL_NAME NTYPE MESSAGE SESSION_ID CWD <<< "$(
  printf '%s' "$INPUT" | jq -r '[
    (.hook_event_name // ""),
    (.tool_name // ""),
    (.notification_type // ""),
    (.message // ""),
    (.session_id // ""),
    (.cwd // "")
  ] | @tsv'
)"

if [[ "$HOOK_EVENT" == "PreToolUse" ]]; then
  case "$TOOL_NAME" in
    AskUserQuestion) NTYPE="ask_user_question" ;;
    ExitPlanMode)    NTYPE="plan_approval" ;;
    *)               exit 0 ;;
  esac
  MESSAGE=""
else
  # Only notify for types where Claude is blocked waiting for the user.
  case "$NTYPE" in
    permission_prompt|idle_prompt|elicitation_dialog) ;;
    *) exit 0 ;;
  esac
fi

# --- Shared state ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
[[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- Resolve tmux pane context (single tmux call) ---
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

# --- Resolve attention color and icon (Catppuccin Mocha) ---
# Shared attention color/icon mapping (stowed to ~/.local/bin).
# shellcheck disable=SC1091
source "${HOME}/.local/bin/tmux-attention-lib" 2>/dev/null || true
if ! declare -f resolve_attention >/dev/null 2>&1; then
  # Fallback if lib not stowed yet -- skip visual indicators.
  resolve_attention() { _attn_color=""; _attn_icon=""; _attn_priority=9; }
fi
resolve_attention "$NTYPE"
ATTN_COLOR=$_attn_color
ATTN_ICON=$_attn_icon
ATTN_PRIORITY=$_attn_priority

# --- Write attention marker for tmux-attention switcher ---
# Written before the dedup cooldown so rapid re-prompts still register a
# marker even when the desktop notification is suppressed.
if [[ -n "${TMUX_PANE:-}" ]]; then
  ATTN_DIR="${CACHE_DIR}/attention"
  [[ -d "$ATTN_DIR" ]] || mkdir -p "$ATTN_DIR" 2>/dev/null || true
  MARKER_TMP=$(mktemp "${ATTN_DIR}/.tmp.XXXXXX" 2>/dev/null) || true
  if [[ -n "${MARKER_TMP:-}" ]]; then
    printf '%s\n' \
      "pane_id=${TMUX_PANE}" \
      "pane_label=${PANE_LABEL}" \
      "notification_type=${NTYPE}" \
      "project=${PROJECT}" \
      "cwd=${CWD}" \
      "timestamp=${EPOCHSECONDS}" \
      > "$MARKER_TMP" 2>/dev/null || true
    mv -f "$MARKER_TMP" "${ATTN_DIR}/${TMUX_PANE}" 2>/dev/null || true
  fi

  # --- Set tmux visual indicators for non-idle types ---
  if [[ -n "$ATTN_COLOR" ]]; then
    # Per-pane: color the border.
    tmux set-option -p -t "$TMUX_PANE" pane-border-style "fg=${ATTN_COLOR}" \
      2>/dev/null || true

    # Per-window: set @attention icon/color (only if this type is more urgent).
    WINDOW_ID=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null || true)
    if [[ -n "$WINDOW_ID" ]]; then
      CUR_PRI=$(tmux show-option -wqv -t "$WINDOW_ID" @attention_priority 2>/dev/null || true)
      if [[ -z "$CUR_PRI" ]] || (( ATTN_PRIORITY <= CUR_PRI )); then
        tmux set-option -w -t "$WINDOW_ID" @attention "1" 2>/dev/null || true
        tmux set-option -w -t "$WINDOW_ID" @attention_color "$ATTN_COLOR" 2>/dev/null || true
        tmux set-option -w -t "$WINDOW_ID" @attention_icon "$ATTN_ICON" 2>/dev/null || true
        tmux set-option -w -t "$WINDOW_ID" @attention_priority "$ATTN_PRIORITY" 2>/dev/null || true
      fi
    fi
  fi
fi

# --- Deduplication: 10-second cooldown per session ---
# Only gates desktop notifications and bell below -- markers are already written.
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

# --- Build notification title and body ---
TITLE="Claude Code"
case "$NTYPE" in
  permission_prompt)  TITLE="Approval Needed" ;;
  idle_prompt)        TITLE="Task Complete" ;;
  elicitation_dialog) TITLE="Input Needed" ;;
  ask_user_question)  TITLE="Question" ;;
  plan_approval)      TITLE="Plan Review" ;;
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
