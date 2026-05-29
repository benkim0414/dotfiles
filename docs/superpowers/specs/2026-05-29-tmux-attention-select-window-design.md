# tmux attention: switch to the correct window, not just the session

## Problem

When a tmux session has more than one window, the tmux attention pickers
switch to the right *session* but land on the *wrong window*. Selecting a
list item for a pane in window 1 leaves the client showing window 0.

## Root cause

Both `switch_to_pane` helpers do:

```bash
session=$(tmux display-message -t "$pane_id" -p '#{session_name}')
tmux switch-client -t "$session"
tmux select-pane -t "$pane_id"
```

`select-pane` makes a pane the active pane *within its own window*, but it
does not change which window the session currently displays. That is the job
of `select-window`. With a single-window session the bug is invisible (the
pane's window is already current); with multiple windows the client stays on
whatever window was active.

Affected call sites (identical bug, shared root cause):

- `bin/.local/bin/tmux-attention-picker` — `switch_to_pane`, lines 150-156
  (bound to `Prefix+A`, fzf popup picker).
- `bin/.local/bin/tmux-attention` — `switch_to_pane`, lines 53-66 (bound to
  `Prefix+a`; used by both dispatch mode and `--pick` mode).

## Fix

Approach A: add a single `select-window` call in each `switch_to_pane`,
between the existing `switch-client` and `select-pane` calls. Keep the
explicit `session_name` query (it exists to handle session names containing
colons) and keep the per-command `2>/dev/null || true` fault tolerance.

Resulting target sequence in both functions:

```bash
tmux switch-client -t "$session" 2>/dev/null || true   # right session
tmux select-window -t "$pane_id" 2>/dev/null || true   # right window  <-- added
tmux select-pane  -t "$pane_id" 2>/dev/null || true    # right pane
```

`select-window -t "$pane_id"` resolves the pane id to its containing window
and makes that window current, so the subsequent `select-pane` lands the
cursor on the intended pane in the now-visible window.

### Rejected alternatives

- **B — retarget all calls to `$pane_id`** (drop the `session_name` query,
  use `switch-client -t "$pane_id"`): discards the deliberate colon-safe
  session handling and changes session-switch behavior for no functional
  gain.
- **C — single chained `tmux ... \; ... \; ...` command**: cosmetic only;
  same effect as A but harder to preserve the per-command error suppression.

## Scope

Two files, one added line each. No change to marker parsing, status
resolution, sorting, fzf invocation, or the badge script
(`tmux-attention-badge` has no `switch_to_pane`). The `tmux-attention`
`switch_to_pane` also removes the marker after switching; that behavior is
unchanged.

## Testing

No automated test harness exists for these scripts (no test directory under
`bin/`). Verification is manual, reproducing the reported case:

1. One tmux session with two windows; an AI pane (Claude Code or Codex) in
   window 1 with an active attention marker, window 0 currently focused.
2. `Prefix+A`, select the window-1 entry → client lands on window 1 with the
   target pane active.
3. `Prefix+a` dispatch (single waiting pane in window 1) → same result.
4. Regression: single-window session still switches correctly.
