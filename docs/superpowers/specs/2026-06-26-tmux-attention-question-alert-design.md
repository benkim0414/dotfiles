# tmux-attention: alert + status for AskUserQuestion / ExitPlanMode

Date: 2026-06-26
Status: design approved

## Problem

When Claude Code blocks on an `AskUserQuestion` prompt (the native
multiple-choice picker) or an `ExitPlanMode` plan-approval prompt, the
tmux-attention system shows **nothing** — no desktop alert (Ghostty OSC 777 +
bell), and no tmux status badge / picker icon. The same system works correctly
for permission prompts, idle prompts, and MCP elicitation dialogs.

## Root cause

`AskUserQuestion` and `ExitPlanMode` are wired through the **PreToolUse** branch
of `claude/.claude/hooks/notify.sh` (matcher `AskUserQuestion|ExitPlanMode`,
`async: true`). Empirical investigation established:

1. `notify.sh` logic is correct — given a PreToolUse `AskUserQuestion` payload
   with `TMUX_PANE` set, it writes a valid `ask_user_question` marker.
2. On a real `AskUserQuestion` round-trip, the per-session cooldown file
   (`~/.cache/claude/notify-<session_id>`) **was bumped** — proving the hook
   ran to completion (the cooldown write is late in the script).
3. Yet **no marker** was written for the pane, and the test occurred with no
   pane-focus change, so `--clear-focused` could not have removed it.
4. Notification-path markers (e.g. `permission_prompt`) carry a correct
   `pane_id` / `pane_label`, proving `TMUX_PANE` **is** present for Notification
   hooks.

Conclusion: the async **PreToolUse** hook invocation runs with `TMUX_PANE`
empty. The marker-write block and the OSC 777 + bell block are both guarded on
`TMUX_PANE` / a resolved `PANE_TTY`, so both are skipped — explaining the
missing status **and** the missing alert simultaneously. The cooldown block is
keyed on `SESSION_ID`, so it survives. Notification hooks receive `TMUX_PANE`;
PreToolUse hooks (at least async ones) do not.

This is a Claude Code env-propagation difference between hook events. The fix
makes `notify.sh` self-sufficient rather than depending on the inherited
`TMUX_PANE`.

## Approach (approved: A — pane resolution via process ancestry)

When `TMUX_PANE` is empty, recover the pane id by walking the process-parent
chain up to the `claude`/`codex` process and matching its pid against tmux's
`#{pane_pid}` → `#{pane_id}` table. This is the same ppid→pane_pid technique
already used by `tmux-attention-picker`, so it is proven in this repo. It is a
no-op when `TMUX_PANE` is already populated, and harmless (returns empty)
outside tmux.

Rejected alternatives:
- **TTY-based resolution** — async hooks are typically spawned detached with no
  controlling tty, so matching `#{pane_tty}` would fail for exactly this case.
- **Inject pane via settings command** — `settings.json` cannot reliably
  interpolate `TMUX_PANE`; it is the same missing-env problem, unsolved.

## Components

### 1. Diagnostic (plan step 1 — throwaway, confirms mechanism)

Before changing `notify.sh`, confirm exactly what env the PreToolUse hook sees.
Add a temporary PreToolUse `AskUserQuestion` hook entry to the dotfiles repo's
**`.claude/settings.local.json`** (gitignored; the sanctioned per-repo override
surface — avoids editing the stowed main file and the worktree-guard). The temp
hook logs `TMUX`, `TMUX_PANE`, `tty`, and the `$PPID` ancestry to a scratchpad
file. Trigger one real `AskUserQuestion`, read the log, then remove the temp
hook entry.

Outcome gates the resolver: confirms whether the ancestry walk has the data it
needs (a reachable `claude`/`codex` ancestor pid and a populated tmux pane
table), and confirms `TMUX_PANE` is indeed the empty variable.

### 2. Pane resolver in `notify.sh`

New helper, called early in `main()`:

```
resolve_pane_id():
  if TMUX_PANE non-empty            -> echo "$TMUX_PANE"; return
  if TMUX empty                     -> return (no tmux, nothing to resolve)
  # Build pid -> ppid map once (ps -eo pid=,ppid=).
  # Walk from $PPID upward (cap depth ~5) until a pid matches a claude/codex
  # process, OR collect ancestor pids.
  # Read tmux list-panes -a -F '#{pane_pid}\t#{pane_id}' once.
  # Echo the pane_id whose pane_pid is in the ancestor set.
```

`main()` assigns `TMUX_PANE="$(resolve_pane_id)"` (overwriting only when it was
empty). All downstream blocks — marker write, `PANE_LABEL`/`PANE_TTY` lookup,
OSC 777, bell — then work unchanged.

Constraints:
- Bounded ancestry walk (depth cap) — no runaway loops.
- Every `tmux` / `ps` call wrapped `|| true` — the async hook must never fail
  Claude Code (exit 0 always preserved).
- Single `ps` pass and single `tmux list-panes` pass (hot-path discipline,
  matching the existing `perf(claude)` subprocess-fork reductions).
- No behavior change when `TMUX_PANE` is present (regression-safe).

### 3. Tests

New hermetic test under `claude/.claude/tests/` following the existing
`notify`/`permission-policy`/`commit-scope` test convention (a `run.sh` that
PATH-shims `tmux` and `ps` so no live tmux is required). Cases:

1. `TMUX_PANE` set → used verbatim; marker written for that pane (regression).
2. `TMUX_PANE` empty + mocked ancestry resolving to a pane → marker written
   for the resolved pane with `notification_type=ask_user_question`.
3. `TMUX_PANE` empty + `TMUX` empty → no marker, exit 0, no error.
4. (If cheap) `ExitPlanMode` payload → `notification_type=plan_approval`
   marker via the same resolver.

## Scope / boundaries

- Files changed: `claude/.claude/hooks/notify.sh` and one new test file. Plus
  the throwaway `.claude/settings.local.json` diagnostic entry (added and
  removed within step 1; gitignored, never committed).
- Consumers (`tmux-attention`, `tmux-attention-badge`, `tmux-attention-picker`)
  already handle `ask_user_question` and `plan_approval` — untouched.
- Fixes `AskUserQuestion` **and** `ExitPlanMode` together (shared PreToolUse
  path).
- Notification path unchanged (already correct).

## Verification

- New tests pass (`bash claude/.claude/tests/<dir>/run.sh`).
- `shellcheck` clean on `notify.sh` (repo convention).
- Live: trigger an `AskUserQuestion` → confirm a `%<pane>` marker with
  `notification_type=ask_user_question` appears in
  `~/.cache/claude/attention/` AND the OSC 777 desktop notification + tmux bell
  fire. Repeat for `ExitPlanMode` → `plan_approval`.

## Workflow

no-pr mode: this spec (worktree) → writing-plans → implementation →
requesting-code-review → ce-compound → finishing-a-development-branch option 1
(local merge).
