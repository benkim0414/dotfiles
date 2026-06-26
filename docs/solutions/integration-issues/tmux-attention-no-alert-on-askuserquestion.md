---
title: "tmux-attention showed no alert/status for AskUserQuestion and ExitPlanMode prompts"
date: 2026-06-26
category: integration-issues
module: claude
problem_type: integration_issue
component: tooling
symptoms:
  - "No Ghostty OSC-777 desktop notification or tmux bell when Claude Code blocks on an AskUserQuestion multiple-choice prompt"
  - "No ' 󰂚 N waiting' status-bar badge and no picker icon while a question/plan-approval prompt is open"
  - "Permission prompts, idle prompts, and MCP elicitation dialogs alert correctly — only AskUserQuestion/ExitPlanMode are silent"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
related_components:
  - tooling
tags:
  - tmux
  - claude-hooks
  - notify
  - tmux-attention
  - PreToolUse
  - TMUX_PANE
---

# tmux-attention showed no alert/status for AskUserQuestion and ExitPlanMode prompts

## Problem

`tmux-attention` (driven by `claude/.claude/hooks/notify.sh`) produced no
desktop alert and no tmux status badge when Claude Code blocked on an
`AskUserQuestion` or `ExitPlanMode` prompt, even though it worked for permission
prompts, idle prompts, and MCP elicitation dialogs.

## Symptoms

- No OSC-777 notification and no tmux bell while an `AskUserQuestion` prompt is open.
- No ` 󰂚 N waiting` status badge and no picker entry for the waiting pane.
- The same machinery works for `permission_prompt`, `idle_prompt`, and
  `elicitation_dialog` — the gap is specific to the two prompts wired through
  the `PreToolUse` branch.

## What Didn't Work

- **Assuming the consumers were broken.** `tmux-attention`, `-badge`, and
  `-picker` already handle `ask_user_question` and `plan_approval` markers
  (priority, labels, icons). They were never the problem.
- **Assuming `notify.sh` had a logic bug.** Fed a synthetic `PreToolUse`
  `AskUserQuestion` payload with `TMUX_PANE` set, the script wrote a correct
  marker. The logic was fine given the right input.
- **Assuming the hook never fired (docs say `PreToolUse` matches
  `AskUserQuestion`).** The official docs confirm `PreToolUse` fires for
  `AskUserQuestion`/`ExitPlanMode`, and that `AskUserQuestion` emits **no**
  `Notification` event — so `PreToolUse` is the only available hook. A
  controlled live probe then proved the hook *did* run.

The decisive experiment: `notify.sh` writes a per-session cooldown file
(`~/.cache/claude/notify-<session_id>`) late in its body, after the
marker-write block. Capturing that file's mtime before/after a real
`AskUserQuestion` showed it **bumped** (hook ran to completion) while **no pane
marker** was written and the test involved no pane-focus change (so
`--clear-focused` could not have removed it). Marker-write and OSC-777/bell are
both guarded on `$TMUX_PANE`/`$PANE_TTY`; the cooldown is keyed on
`session_id`. Only one variable explains a cooldown bump with no marker and no
alert: `$TMUX_PANE` was empty.

## Solution

Claude Code **`Notification` hooks inherit `$TMUX_PANE`, but async `PreToolUse`
hooks do not.** Make `notify.sh` self-sufficient instead of depending on the
inherited variable.

New lib `claude/.claude/lib/notify-pane.sh` exposing `notify_resolve_pane_id`,
which recovers the pane id from process ancestry when `$TMUX_PANE` is empty —
the pane's shell is an ancestor of the hook process:

```bash
notify_resolve_pane_id() {
  [[ -n "${TMUX_PANE:-}" ]] && { printf '%s\n' "$TMUX_PANE"; return 0; }  # fast path
  [[ -n "${TMUX:-}" ]] || return 0                                         # not in tmux

  local -A ppid_map=()
  local pid ppid
  while read -r pid ppid; do
    [[ -n "$pid" ]] && ppid_map[$pid]=$ppid
  done < <(ps -eo pid=,ppid= 2>/dev/null || true)

  local -A ancestors=()
  local cur="$PPID" depth=0
  while [[ -n "$cur" && "$cur" != 0 ]] && (( depth < 10 )); do
    ancestors[$cur]=1; cur="${ppid_map[$cur]:-}"; (( depth++ )) || true
  done

  local pane_pid pane_id
  while IFS=$'\t' read -r pane_pid pane_id; do
    [[ -n "${ancestors[$pane_pid]:-}" ]] && { printf '%s\n' "$pane_id"; return 0; }
  done < <(tmux list-panes -a -F '#{pane_pid}'$'\t''#{pane_id}' 2>/dev/null || true)
  return 0
}
```

`notify.sh` sources the lib (matching the sibling hooks' symlink-resolving
idiom, guarded so a missing lib degrades gracefully) and reassigns `TMUX_PANE`
early in `main()`, before the marker and tty blocks:

```bash
# shellcheck source=../lib/notify-pane.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/notify-pane.sh" 2>/dev/null || true
...
if declare -F notify_resolve_pane_id >/dev/null 2>&1; then
  TMUX_PANE="$(notify_resolve_pane_id)"
fi
```

The fast path returns an already-set `$TMUX_PANE` verbatim, so the
`Notification` path is unchanged. Fixes both `AskUserQuestion`
(`ask_user_question`) and `ExitPlanMode` (`plan_approval`) — they share the
`PreToolUse` path.

## Why This Works

The root cause is an interface assumption: `notify.sh` relied on `$TMUX_PANE`
being present, which holds for `Notification` hooks but not for async
`PreToolUse` hooks. Process ancestry is a reliable, hook-event-agnostic way to
find the pane: the hook is a descendant of the `claude` process, which is a
descendant of the pane's shell, whose pid is the pane's `#{pane_pid}`. Walking
up from `$PPID` and matching against tmux's pane table recovers the correct
pane regardless of which hook event fired. (`$PPID` is stable inside the
command-substitution subshell, so it still names the hook's real parent.)
Notably, `tmux display-message` *without* `-t` returns the wrong pane from a
detached hook context — ancestry resolution is more correct than asking tmux
for the "current" pane.

## Prevention

- **Don't assume hook events share an environment.** `Notification` and
  `PreToolUse` hooks do not expose the same env. Verify which vars a given hook
  event actually provides before depending on them; the `PreToolUse` JSON
  payload carries no pane/tty info, so pane context must be derived.
- **Instrument with a late-write side effect to prove a hook ran.** The
  cooldown-file mtime (written after the suspect block) distinguished "hook
  never fired" from "hook fired but the guarded block was skipped" without
  editing the live hook. Pick an observable that sits *downstream* of the code
  under suspicion.
- **Guard async-hook lib coupling.** Source with
  `... 2>/dev/null || true` and gate the call with `declare -F`, so a
  half-stowed deploy degrades to the old behavior instead of failing an
  `async: true` hook (which must always exit 0).
- **Test the resolver hermetically.** `claude/.claude/tests/notify-pane/`
  PATH-shims `tmux`/`ps` and drives the real hook end-to-end; one case covers
  the no-ancestor-match path so the empty-resolution safety net (no
  wrong/empty-named marker) stays locked in.
