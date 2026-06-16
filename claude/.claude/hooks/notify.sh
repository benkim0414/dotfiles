#!/usr/bin/env bash
# notify.sh — alert the user (Ghostty OSC 777 + tmux bell) when Claude needs
#             attention.
#
# Event:   Notification and PreToolUse
# Matcher: AskUserQuestion|ExitPlanMode (PreToolUse); all Notification events
# Exit:    0 always.
# Async:   yes — must never slow down Claude Code.
#
# Called from two hook contexts; detects its context via hook_event_name:
#   Notification   -- permission_prompt, idle_prompt, elicitation_dialog
#   PreToolUse     -- AskUserQuestion, ExitPlanMode
set -euo pipefail

: "${EPOCHSECONDS:=$(date +%s)}"

# --- Send Ghostty desktop notification via OSC 777 ---
# Outputs the OSC 777 escape sequence to a tty; wraps in tmux DCS passthrough
# when inside tmux so the sequence reaches Ghostty.
# Globals:   TMUX (read)
# Arguments: $1 title, $2 body, $3 target tty/device path
# Outputs:   OSC 777 escape sequence written to $3
# Returns:   propagates the printf status
# shellcheck disable=SC1003  # ShellCheck misreads \a\e\\ as a quote escape; \a is BEL in printf
send_osc777() {
  local title="$1" body="$2" target="$3"
  if [[ -n "${TMUX:-}" ]]; then
    # Wrap in DCS passthrough so tmux forwards to Ghostty.
    printf '\ePtmux;\e\e]777;notify;%s;%s\a\e\\' "$title" "$body" >"$target"
  else
    # Direct Ghostty (no tmux).
    printf '\e]777;notify;%s;%s\a' "$title" "$body" >"$target"
  fi
}

# Entry point: parse the hook payload, write the tmux attention marker, then
# (subject to a per-session cooldown) emit the desktop notification + bell.
# Globals:   reads stdin (hook JSON); reads TMUX, TMUX_PANE, EPOCHSECONDS,
#            XDG_CACHE_HOME, HOME; writes cache + attention marker files
# Arguments: none (payload arrives on stdin)
# Outputs:   OSC 777 notification + tmux bell on the target pane tty
# Returns:   always 0 (async hook must never fail Claude Code)
main() {
  INPUT=$(cat)
  HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""')

  if [[ "$HOOK_EVENT" == "PreToolUse" ]]; then
    # Called from PreToolUse -- map tool name to notification type.
    IFS=$'\t' read -r TOOL_NAME SESSION_ID CWD <<<"$(
      printf '%s' "$INPUT" | jq -r '[
        (.tool_name // ""),
        (.session_id // ""),
        (.cwd // "")
      ] | @tsv'
    )"
    case "$TOOL_NAME" in
      AskUserQuestion) NTYPE="ask_user_question" ;;
      ExitPlanMode) NTYPE="plan_approval" ;;
      *) exit 0 ;;
    esac
    MESSAGE=""
  else
    # Called from Notification hook.
    IFS=$'\t' read -r NTYPE MESSAGE SESSION_ID CWD <<<"$(
      printf '%s' "$INPUT" | jq -r '[
        (.notification_type // ""),
        (.message // ""),
        (.session_id // ""),
        (.cwd // "")
      ] | @tsv'
    )"
    # Only notify for types where Claude is blocked waiting for the user.
    case "$NTYPE" in
      permission_prompt | idle_prompt | elicitation_dialog) ;;
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
    IFS=$'\t' read -r PANE_LABEL PANE_TTY <<<"$(
      tmux display-message -t "$TMUX_PANE" \
        -p '#{session_name}:#{window_index}.#{pane_index}'$'\t''#{pane_tty}' 2>/dev/null || true
    )"
  fi

  # Short project name from cwd.
  PROJECT=""
  if [[ -n "$CWD" ]]; then
    PROJECT=$(basename "$CWD")
  fi

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
        >"$MARKER_TMP" 2>/dev/null || true
      mv -f "$MARKER_TMP" "${ATTN_DIR}/${TMUX_PANE}" 2>/dev/null || true
    fi
  fi

  # --- Deduplication: 10-second cooldown per session ---
  # Only gates desktop notifications and bell below -- markers are already written.
  if [[ -n "$SESSION_ID" ]]; then
    COOLDOWN_FILE="${CACHE_DIR}/notify-${SESSION_ID}"
    NOW=$EPOCHSECONDS
    if [[ -f "$COOLDOWN_FILE" ]]; then
      LAST=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
      if ((NOW - LAST < 10)); then
        exit 0
      fi
    fi
    printf '%s' "$NOW" >"$COOLDOWN_FILE" 2>/dev/null || true
  fi

  # --- Build notification title and body ---
  TITLE="Claude Code"
  case "$NTYPE" in
    permission_prompt) TITLE="Approval Needed" ;;
    idle_prompt) TITLE="Task Complete" ;;
    elicitation_dialog) TITLE="Input Needed" ;;
    ask_user_question) TITLE="Question" ;;
    plan_approval) TITLE="Plan Review" ;;
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

  # --- Send the notification to the resolved pane tty ---
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
    printf '\a' >"$PANE_TTY"
  fi

  exit 0
}

main "$@"
