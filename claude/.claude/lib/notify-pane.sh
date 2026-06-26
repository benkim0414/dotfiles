#!/usr/bin/env bash
# notify-pane.sh — resolve the tmux pane id for the calling hook process.
#
# Async PreToolUse hooks (AskUserQuestion, ExitPlanMode) run without an
# inherited $TMUX_PANE, unlike Notification hooks. This recovers the pane id
# from process ancestry: walk up from $PPID and match any ancestor pid against
# tmux's #{pane_pid} -> #{pane_id} table (the pane's shell is an ancestor of
# the hook). Sourced by hooks/notify.sh.

# Resolve a tmux pane id for the calling process.
# Globals:   reads TMUX_PANE, TMUX, PPID
# Outputs:   pane id (e.g. "%246") on stdout, or nothing if unresolvable
# Returns:   0 always (callers must never fail on this)
notify_resolve_pane_id() {
  # Fast path: pane id already in the environment (Notification hooks).
  if [[ -n "${TMUX_PANE:-}" ]]; then
    printf '%s\n' "$TMUX_PANE"
    return 0
  fi

  # Outside tmux there is nothing to resolve.
  [[ -n "${TMUX:-}" ]] || return 0

  # Build pid -> ppid map in one pass.
  local -A ppid_map=()
  local pid ppid
  while read -r pid ppid; do
    [[ -n "$pid" ]] && ppid_map[$pid]=$ppid
  done < <(ps -eo pid=,ppid= 2>/dev/null || true)

  # Collect ancestor pids by walking up from this process (bounded depth).
  local -A ancestors=()
  local cur="$PPID" depth=0
  while [[ -n "$cur" && "$cur" != 0 ]] && (( depth < 10 )); do
    ancestors[$cur]=1
    cur="${ppid_map[$cur]:-}"
    (( depth++ )) || true
  done

  # Return the pane whose pane_pid is one of our ancestors.
  local pane_pid pane_id
  while IFS=$'\t' read -r pane_pid pane_id; do
    if [[ -n "${ancestors[$pane_pid]:-}" ]]; then
      printf '%s\n' "$pane_id"
      return 0
    fi
  done < <(tmux list-panes -a -F '#{pane_pid}'$'\t''#{pane_id}' 2>/dev/null || true)

  return 0
}
