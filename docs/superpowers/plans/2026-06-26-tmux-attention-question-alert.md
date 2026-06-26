# tmux-attention Question/Plan Alert Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tmux-attention show its desktop alert (OSC 777 + bell) and tmux status badge when Claude Code blocks on an `AskUserQuestion` or `ExitPlanMode` prompt.

**Architecture:** The async PreToolUse hook (`notify.sh`) runs with `$TMUX_PANE` empty (Notification hooks inherit it; PreToolUse hooks do not), so its pane-guarded marker-write and OSC-777 blocks are skipped. Add a sourceable lib `notify-pane.sh` exposing `notify_resolve_pane_id`, which recovers the pane id from process ancestry (walk `$PPID` up, match against tmux `#{pane_pid}`→`#{pane_id}`) when `$TMUX_PANE` is empty. `notify.sh` assigns the resolved value to `TMUX_PANE` early in `main()`; all downstream blocks then work unchanged.

**Tech Stack:** Bash (4+, associative arrays — already required by `tmux-attention-picker`), tmux, GNU Stow symlinks, hermetic shell tests with PATH-shimmed `tmux`/`ps`.

## Global Constraints

- The hook MUST always exit 0 — it is `async: true` and must never fail Claude Code. Wrap every `tmux`/`ps` call with `|| true`.
- No behavior change when `$TMUX_PANE` is already populated (Notification path must stay identical).
- Bounded ancestry walk (depth cap 10) — no unbounded loops.
- Single `ps` pass and single `tmux list-panes` pass (hot-path discipline, per the existing `perf(claude)` fork-reduction work).
- Lib + hook + test triad convention: pure functions in `claude/.claude/lib/`, sourced by the hook, tested under `claude/.claude/tests/<name>/`.
- Files changed: `claude/.claude/lib/notify-pane.sh` (new), `claude/.claude/hooks/notify.sh` (modify), `claude/.claude/tests/notify-pane/**` (new). Consumers (`tmux-attention*`) are untouched.
- Fixes `AskUserQuestion` (`ask_user_question`) AND `ExitPlanMode` (`plan_approval`) — shared path.

---

## Task 1: Live diagnostic — confirm the env the PreToolUse hook sees

**Purpose:** Before writing the resolver, confirm empirically (per spec) that the PreToolUse hook runs with `$TMUX_PANE` empty and that a `claude`/`codex` ancestor pid is reachable for the ancestry walk. This is an **orchestrator/interactive** task — it requires triggering a real `AskUserQuestion`, which a subagent cannot do.

**Files:**
- Temp (uncommitted, gitignored): `.claude/settings.local.json` — add an additive diagnostic PreToolUse hook.
- Log: `<scratchpad>/notify-diag.log`

**Interfaces:**
- Produces: a confirmed answer to "is `$TMUX_PANE` empty in the PreToolUse hook?" — gates nothing in code (approach A is robust either way) but validates the resolver design.

- [ ] **Step 1: Add the additive diagnostic hook to `.claude/settings.local.json`**

Hooks arrays concatenate with the base, so this runs *alongside* the existing `notify.sh` hook without removing it. Merge this into the repo root `.claude/settings.local.json` (create the file if absent; if it exists, add the `PreToolUse` array entry):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion|ExitPlanMode",
        "hooks": [
          {
            "type": "command",
            "command": "{ echo \"--- $(date) event=$(jq -r .hook_event_name 2>/dev/null) ---\"; echo \"TMUX=${TMUX:-<empty>}\"; echo \"TMUX_PANE=${TMUX_PANE:-<empty>}\"; echo \"tty=$(tty 2>/dev/null || echo none)\"; echo \"PPID=$PPID\"; ps -eo pid=,ppid=,comm= | grep -Ei 'claude|codex' | head; } >> \"$HOME/notify-diag.log\" 2>&1"
          }
        ]
      }
    ]
  }
}
```

(Log goes to `$HOME/notify-diag.log` — settings hook commands don't expand the scratchpad path; move/clean it after.)

- [ ] **Step 2: Reload settings**

Hook changes are picked up on session start. Either start a fresh Claude Code session in this pane, or confirm the running session re-reads `settings.local.json`. Announce to the user that a reload may be needed.

- [ ] **Step 3: Trigger a real AskUserQuestion and read the log**

Ask the user any one-line clarifying question via the AskUserQuestion tool. Then:

Run: `cat "$HOME/notify-diag.log"`
Expected: a block showing `TMUX_PANE=<empty>` (confirming root cause) and at least one `claude`/`codex` line from `ps` (confirming the ancestry walk has a target).

- [ ] **Step 4: Remove the diagnostic and clean up**

Remove the `PreToolUse` diagnostic entry from `.claude/settings.local.json` (restore the file to its prior state, or delete it if it was created solely for this).

Run: `rm -f "$HOME/notify-diag.log"`

- [ ] **Step 5: Record the finding**

No commit (nothing tracked changed). Note the observed `TMUX_PANE` value in the session for Task 4's expectations.

---

## Task 2: `notify-pane.sh` lib + unit tests

**Files:**
- Create: `claude/.claude/lib/notify-pane.sh`
- Create: `claude/.claude/tests/notify-pane/run.sh`
- Create: `claude/.claude/tests/notify-pane/helpers.sh`
- Create: `claude/.claude/tests/notify-pane/cases/01-env-pane-set.sh`
- Create: `claude/.claude/tests/notify-pane/cases/02-no-tmux.sh`
- Create: `claude/.claude/tests/notify-pane/cases/03-ancestry-resolve.sh`

**Interfaces:**
- Produces: `notify_resolve_pane_id()` — reads globals `TMUX_PANE`, `TMUX`, `PPID`; writes a tmux pane id (e.g. `%246`) to stdout, or nothing if unresolvable; always returns 0.

- [ ] **Step 1: Write the test runner**

Create `claude/.claude/tests/notify-pane/run.sh`:

```bash
#!/usr/bin/env bash
# notify-pane lib + hook test runner.
# Iterates cases/*.sh; each case sources helpers.sh and uses assert_* helpers.
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_HOME="$HERE"
export LIB="$HERE/../../lib/notify-pane.sh"
export HOOK="$HERE/../../hooks/notify.sh"

[[ -f "$LIB" ]] || { echo "missing lib: $LIB" >&2; exit 2; }

pass=0; fail=0; failed_cases=()
for case in "$HERE"/cases/*.sh; do
  [[ -e "$case" ]] || continue
  name="$(basename "$case" .sh)"
  if ( cd "$HERE" && bash "$case" ); then
    printf "  PASS  %s\n" "$name"; pass=$((pass+1))
  else
    printf "  FAIL  %s\n" "$name"; fail=$((fail+1)); failed_cases+=("$name")
  fi
done

printf "\nnotify-pane: %d passed, %d failed\n" "$pass" "$fail"
if (( fail > 0 )); then
  printf "failed cases: %s\n" "${failed_cases[*]}"
  exit 1
fi
exit 0
```

- [ ] **Step 2: Write the test helpers**

Create `claude/.claude/tests/notify-pane/helpers.sh`:

```bash
# helpers.sh — shared setup for notify-pane tests.
# Sourced by each case. Provides mock tmux/ps on PATH + assert helpers.
set -uo pipefail

: "${LIB:?LIB must be set by run.sh}"
: "${HOOK:?HOOK must be set by run.sh}"

# Create an isolated temp dir and a mock-bin on PATH.
# Sets globals: TMPROOT, MOCKBIN. Mock ps/tmux read fixture files named by
# the MOCK_PS_FILE / MOCK_PANES_FILE env vars (empty output if unset).
setup_mocks() {
  TMPROOT="$(mktemp -d)"
  MOCKBIN="$TMPROOT/bin"
  mkdir -p "$MOCKBIN"

  cat > "$MOCKBIN/ps" <<'EOF'
#!/usr/bin/env bash
# Mock ps: ignore args, emit the pid/ppid fixture.
cat "${MOCK_PS_FILE:-/dev/null}" 2>/dev/null || true
EOF

  cat > "$MOCKBIN/tmux" <<'EOF'
#!/usr/bin/env bash
# Mock tmux: list-panes emits the pane fixture; display-message emits an
# empty (tab-separated) label/tty so the hook's marker block still runs.
case "${1:-}" in
  list-panes)      cat "${MOCK_PANES_FILE:-/dev/null}" 2>/dev/null || true ;;
  display-message) printf '\t' ;;
  *)               : ;;
esac
EOF

  chmod +x "$MOCKBIN/ps" "$MOCKBIN/tmux"
  export PATH="$MOCKBIN:$PATH"
}

teardown_mocks() { [[ -n "${TMPROOT:-}" ]] && rm -rf "$TMPROOT"; }

assert_eq() {
  local got="$1" want="$2" msg="${3:-assert_eq}"
  if [[ "$got" != "$want" ]]; then
    printf '%s FAILED\n  got:  %q\n  want: %q\n' "$msg" "$got" "$want" >&2
    return 1
  fi
}

assert_file() {
  [[ -f "$1" ]] || { printf 'assert_file FAILED: missing %s\n' "$1" >&2; return 1; }
}

assert_grep() {
  grep -q "$1" "$2" || { printf 'assert_grep FAILED: /%s/ not in %s\n' "$1" "$2" >&2; return 1; }
}
```

- [ ] **Step 3: Write the failing unit tests**

Create `claude/.claude/tests/notify-pane/cases/01-env-pane-set.sh`:

```bash
# TMUX_PANE already set -> returned verbatim (Notification-path regression).
source "$TEST_HOME/helpers.sh"
source "$LIB"
export TMUX_PANE="%55" TMUX="fake"
got="$(notify_resolve_pane_id)"
assert_eq "$got" "%55" "env pane returned verbatim"
```

Create `claude/.claude/tests/notify-pane/cases/02-no-tmux.sh`:

```bash
# Not inside tmux -> nothing resolvable.
source "$TEST_HOME/helpers.sh"
source "$LIB"
unset TMUX_PANE TMUX 2>/dev/null || true
got="$(notify_resolve_pane_id)"
assert_eq "$got" "" "no tmux -> empty"
```

Create `claude/.claude/tests/notify-pane/cases/03-ancestry-resolve.sh`:

```bash
# TMUX_PANE empty + TMUX set: resolve pane id by matching an ancestor pid
# against the tmux pane_pid table.
source "$TEST_HOME/helpers.sh"
setup_mocks
trap teardown_mocks EXIT
source "$LIB"

SENT=999001
# Ancestry: this shell's $PPID -> SENT (a fake pane_pid) -> init.
{ printf '%s %s\n' "$PPID" "$SENT"; printf '%s 1\n' "$SENT"; } > "$TMPROOT/ps.txt"
printf '%s\t%s\n' "$SENT" "%TESTPANE" > "$TMPROOT/panes.txt"
export MOCK_PS_FILE="$TMPROOT/ps.txt" MOCK_PANES_FILE="$TMPROOT/panes.txt"
unset TMUX_PANE; export TMUX="fake"

got="$(notify_resolve_pane_id)"
assert_eq "$got" "%TESTPANE" "ancestry resolves pane id"
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bash claude/.claude/tests/notify-pane/run.sh`
Expected: FAIL — `missing lib` (exit 2) because `notify-pane.sh` does not exist yet.

- [ ] **Step 5: Write the lib**

Create `claude/.claude/lib/notify-pane.sh`:

```bash
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
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash claude/.claude/tests/notify-pane/run.sh`
Expected: PASS — `notify-pane: 3 passed, 0 failed`.

- [ ] **Step 7: shellcheck the lib**

Run: `shellcheck claude/.claude/lib/notify-pane.sh`
Expected: no output (clean).

- [ ] **Step 8: Commit**

```bash
git add claude/.claude/lib/notify-pane.sh \
        claude/.claude/tests/notify-pane/run.sh \
        claude/.claude/tests/notify-pane/helpers.sh \
        claude/.claude/tests/notify-pane/cases/01-env-pane-set.sh \
        claude/.claude/tests/notify-pane/cases/02-no-tmux.sh \
        claude/.claude/tests/notify-pane/cases/03-ancestry-resolve.sh
git commit -m "feat(notify): add notify-pane pane-id resolver lib"
```

---

## Task 3: Wire the resolver into `notify.sh` + integration tests

**Files:**
- Modify: `claude/.claude/hooks/notify.sh` (source the lib near the top; set `TMUX_PANE` early in `main()`)
- Create: `claude/.claude/tests/notify-pane/cases/04-hook-askuserquestion.sh`
- Create: `claude/.claude/tests/notify-pane/cases/05-hook-exitplanmode.sh`

**Interfaces:**
- Consumes: `notify_resolve_pane_id()` from Task 2.
- Produces: a `notify.sh` whose PreToolUse path writes an attention marker (and fires OSC 777 + bell) for the resolved pane.

- [ ] **Step 1: Write the failing integration tests**

Create `claude/.claude/tests/notify-pane/cases/04-hook-askuserquestion.sh`:

```bash
# Full hook run: PreToolUse AskUserQuestion, TMUX_PANE empty, TMUX set.
# The resolver recovers the pane id and the marker block writes the marker.
source "$TEST_HOME/helpers.sh"
setup_mocks
trap teardown_mocks EXIT

SENT=999042
# The piped `bash "$HOOK"` process's parent is THIS case shell ($$).
{ printf '%s %s\n' "$$" "$SENT"; printf '%s 1\n' "$SENT"; } > "$TMPROOT/ps.txt"
printf '%s\t%s\n' "$SENT" "%TESTPANE" > "$TMPROOT/panes.txt"
export MOCK_PS_FILE="$TMPROOT/ps.txt" MOCK_PANES_FILE="$TMPROOT/panes.txt"
unset TMUX_PANE; export TMUX="fake"
export XDG_CACHE_HOME="$TMPROOT/cache"

echo '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","session_id":"sess-aq","cwd":"/x/proj"}' \
  | bash "$HOOK"

marker="$TMPROOT/cache/claude/attention/%TESTPANE"
assert_file "$marker"
assert_grep '^notification_type=ask_user_question$' "$marker"
assert_grep '^pane_id=%TESTPANE$' "$marker"
```

Create `claude/.claude/tests/notify-pane/cases/05-hook-exitplanmode.sh`:

```bash
# Full hook run: PreToolUse ExitPlanMode -> plan_approval marker.
source "$TEST_HOME/helpers.sh"
setup_mocks
trap teardown_mocks EXIT

SENT=999043
{ printf '%s %s\n' "$$" "$SENT"; printf '%s 1\n' "$SENT"; } > "$TMPROOT/ps.txt"
printf '%s\t%s\n' "$SENT" "%PLANPANE" > "$TMPROOT/panes.txt"
export MOCK_PS_FILE="$TMPROOT/ps.txt" MOCK_PANES_FILE="$TMPROOT/panes.txt"
unset TMUX_PANE; export TMUX="fake"
export XDG_CACHE_HOME="$TMPROOT/cache"

echo '{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","session_id":"sess-pm","cwd":"/x/proj"}' \
  | bash "$HOOK"

marker="$TMPROOT/cache/claude/attention/%PLANPANE"
assert_file "$marker"
assert_grep '^notification_type=plan_approval$' "$marker"
```

- [ ] **Step 2: Run the tests to verify the new cases fail**

Run: `bash claude/.claude/tests/notify-pane/run.sh`
Expected: cases 04 and 05 FAIL (no `%TESTPANE`/`%PLANPANE` marker) because `notify.sh` does not yet source the resolver — `TMUX_PANE` stays empty and the marker block is skipped. Cases 01-03 still PASS.

- [ ] **Step 3: Source the lib in `notify.sh`**

In `claude/.claude/hooks/notify.sh`, immediately after the `: "${EPOCHSECONDS:=$(date +%s)}"` line (currently line 15), add:

```bash

# Resolve the pane id even when $TMUX_PANE is not inherited. Async PreToolUse
# hooks (AskUserQuestion, ExitPlanMode) don't get $TMUX_PANE; Notification
# hooks do. notify-pane.sh provides notify_resolve_pane_id.
# shellcheck source=../lib/notify-pane.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/notify-pane.sh"
```

- [ ] **Step 4: Set `TMUX_PANE` early in `main()`**

In `main()`, immediately before the `# --- Resolve tmux pane context (single tmux call) ---` comment (currently line 83), add:

```bash
  # Recover $TMUX_PANE when the hook did not inherit it (see notify-pane.sh).
  # Idempotent: echoes the existing value back when already set.
  TMUX_PANE="$(notify_resolve_pane_id)"

```

- [ ] **Step 5: Run all tests to verify they pass**

Run: `bash claude/.claude/tests/notify-pane/run.sh`
Expected: PASS — `notify-pane: 5 passed, 0 failed`.

- [ ] **Step 6: shellcheck the hook**

Run: `shellcheck claude/.claude/hooks/notify.sh`
Expected: no output (clean). The `# shellcheck source=` directive resolves the sourced lib.

- [ ] **Step 7: Commit**

```bash
git add claude/.claude/hooks/notify.sh \
        claude/.claude/tests/notify-pane/cases/04-hook-askuserquestion.sh \
        claude/.claude/tests/notify-pane/cases/05-hook-exitplanmode.sh
git commit -m "fix(notify): resolve pane id so AskUserQuestion/ExitPlanMode alert"
```

---

## Task 4: Live end-to-end verification

**Purpose:** Confirm the real fix on the running system. **Orchestrator/interactive** — requires triggering real prompts; a subagent cannot.

**Files:** none (verification only).

- [ ] **Step 1: Confirm the live hook resolves to the stowed lib**

The live hook is a Stow symlink to the repo. Confirm the lib symlink exists after the change is merged/stowed:

Run: `ls -l "$HOME/.claude/lib/notify-pane.sh"`
Expected: a symlink into the dotfiles `claude/.claude/lib/` package. If absent, run `stow -t ~ claude` from the repo root (note: requires the change merged to the stowed working tree, or re-stow from the worktree path is not how stow is wired — verify post-merge).

- [ ] **Step 2: Clear stale markers for this pane**

Run: `rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/claude/attention/$(tmux display-message -p '#{pane_id}')"`
Expected: no error.

- [ ] **Step 3: Trigger an AskUserQuestion and verify the marker**

Ask the user a one-line clarifying question via the AskUserQuestion tool. While it is displayed, in another pane (do NOT focus this pane — focusing fires `--clear-focused`):

Run: `cat "${XDG_CACHE_HOME:-$HOME/.cache}/claude/attention/"%* 2>/dev/null`
Expected: a marker containing `notification_type=ask_user_question` and the correct `pane_id` for this Claude pane.

- [ ] **Step 4: Verify the desktop alert**

Confirm with the user that a Ghostty desktop notification titled "Question" appeared and the tmux status bar showed the bell + ` 󰂚 N waiting` badge (from `tmux-attention-badge`) while the prompt was open.

- [ ] **Step 5: Verify ExitPlanMode (plan_approval)**

In a quick plan-mode exchange, trigger `ExitPlanMode`. Repeat Step 3's check; expect `notification_type=plan_approval` and a "Plan Review" desktop notification.

- [ ] **Step 6: Record the result**

No commit. Report pass/fail with the observed marker contents to the user. If any check fails, return to systematic-debugging — do not claim completion.

---

## Self-Review

**Spec coverage:**
- Root cause (TMUX_PANE empty for PreToolUse) → Task 1 confirms, Tasks 2-3 fix. ✓
- Approach A (ancestry walk) → Task 2 lib. ✓
- Diagnostic (settings.local.json, throwaway) → Task 1. ✓
- Pane resolver helper → Task 2 (refined to a lib per repo convention; noted). ✓
- Tests (TMUX_PANE set / empty+resolve / neither / ExitPlanMode) → Tasks 2-3 cases 01-05. ✓
- Both AskUserQuestion + ExitPlanMode → cases 04/05, shared wiring. ✓
- Consumers untouched, Notification path unchanged → only notify.sh/lib/tests touched; fast-path returns env value verbatim. ✓
- Verification (tests pass, shellcheck clean, live marker + alert) → Task 2 step 7, Task 3 step 6, Task 4. ✓

**Placeholder scan:** No TBD/TODO; every code/step shows full content. ✓

**Type/name consistency:** `notify_resolve_pane_id` used identically in lib (Task 2) and hook wiring (Task 3). Fixture pane tokens (`%TESTPANE`, `%PLANPANE`) match their assertions. `MOCK_PS_FILE`/`MOCK_PANES_FILE` consistent between helpers and cases. ✓
