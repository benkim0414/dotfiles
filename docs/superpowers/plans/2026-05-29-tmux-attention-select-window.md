# tmux attention select-window fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the tmux attention pickers land on the correct *window*, not just the correct session, by adding a `select-window` call to both `switch_to_pane` helpers.

**Architecture:** Two bash scripts each define a `switch_to_pane` helper that switches session then selects a pane. They omit `select-window`, so multi-window sessions display the wrong window. Add one `select-window -t "$pane_id"` line between the existing `switch-client` and `select-pane` calls in each helper. No behavior changes elsewhere.

**Tech Stack:** Bash, tmux CLI (`switch-client`, `select-window`, `select-pane`).

---

## File Structure

- Modify: `bin/.local/bin/tmux-attention-picker` — `switch_to_pane`, lines 150-156.
- Modify: `bin/.local/bin/tmux-attention` — `switch_to_pane`, lines 53-66.

No new files. No test files (no test harness exists under `bin/`; verification is manual, see Task 3).

---

### Task 1: Fix `tmux-attention-picker`

**Files:**
- Modify: `bin/.local/bin/tmux-attention-picker:150-156`

- [ ] **Step 1: Add `select-window` to `switch_to_pane`**

Current function:

```bash
# Switch to a pane (works across tmux sessions).
switch_to_pane() {
  local pane_id="$1"
  local session
  session=$(tmux display-message -t "$pane_id" -p '#{session_name}' 2>/dev/null || true)
  [[ -n "$session" ]] && tmux switch-client -t "$session" 2>/dev/null || true
  tmux select-pane -t "$pane_id" 2>/dev/null || true
}
```

Replace with (one added line before `select-pane`):

```bash
# Switch to a pane (works across tmux sessions and windows).
switch_to_pane() {
  local pane_id="$1"
  local session
  session=$(tmux display-message -t "$pane_id" -p '#{session_name}' 2>/dev/null || true)
  [[ -n "$session" ]] && tmux switch-client -t "$session" 2>/dev/null || true
  tmux select-window -t "$pane_id" 2>/dev/null || true
  tmux select-pane -t "$pane_id" 2>/dev/null || true
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n bin/.local/bin/tmux-attention-picker`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add bin/.local/bin/tmux-attention-picker
git commit -m "fix(tmux-attention): select window in picker switch_to_pane"
```

---

### Task 2: Fix `tmux-attention`

**Files:**
- Modify: `bin/.local/bin/tmux-attention:53-66`

- [ ] **Step 1: Add `select-window` to `switch_to_pane`**

Current function:

```bash
# Switch to a pane (works across tmux sessions).
# Queries tmux directly for the session name to handle sessions with colons.
switch_to_pane() {
  local pane_id="$1" marker="$2"
  local session
  session=$(tmux display-message -t "$pane_id" -p '#{session_name}' 2>/dev/null || true)

  if [[ -n "$session" ]]; then
    tmux switch-client -t "$session" 2>/dev/null || true
  fi
  tmux select-pane -t "$pane_id" 2>/dev/null || true

  rm -f "$marker"
}
```

Replace with (one added line before `select-pane`):

```bash
# Switch to a pane (works across tmux sessions and windows).
# Queries tmux directly for the session name to handle sessions with colons.
switch_to_pane() {
  local pane_id="$1" marker="$2"
  local session
  session=$(tmux display-message -t "$pane_id" -p '#{session_name}' 2>/dev/null || true)

  if [[ -n "$session" ]]; then
    tmux switch-client -t "$session" 2>/dev/null || true
  fi
  tmux select-window -t "$pane_id" 2>/dev/null || true
  tmux select-pane -t "$pane_id" 2>/dev/null || true

  rm -f "$marker"
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n bin/.local/bin/tmux-attention`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add bin/.local/bin/tmux-attention
git commit -m "fix(tmux-attention): select window in dispatch switch_to_pane"
```

---

### Task 3: Manual verification

No automated harness exists; verify the reported repro by hand. Scripts are stowed to `~/.local/bin`, so the live copies update immediately via symlink (no re-stow needed for in-place edits).

- [ ] **Step 1: Set up a two-window session**

Create one tmux session with two windows. Start Claude Code or Codex in a pane in window 1 (index 1). Trigger an attention state (e.g., let it reach an idle/permission prompt so a marker is written under `~/.cache/{claude,codex}/attention/`). Focus window 0.

- [ ] **Step 2: Verify the picker (Prefix+A)**

Press `Prefix+A`, select the window-1 entry.
Expected: client switches to window 1 with the AI pane active (previously stayed on window 0).

- [ ] **Step 3: Verify dispatch (Prefix+a)**

With a single waiting pane in window 1 and window 0 focused, press `Prefix+a`.
Expected: client lands on window 1, target pane active.

- [ ] **Step 4: Regression — single-window session**

In a session with only one window, trigger attention and use Prefix+a / Prefix+A.
Expected: switches correctly, no error, no behavior change.

---

## Self-Review

**Spec coverage:** Spec's two affected call sites → Tasks 1 and 2. Spec's manual testing section → Task 3. Rejected alternatives B/C are documented in the spec, not implemented — correct. No gaps.

**Placeholder scan:** No TBD/TODO/"handle edge cases". Both code edits show full before/after. Commands are exact with expected output.

**Type consistency:** Helper name `switch_to_pane` and the added `tmux select-window -t "$pane_id"` line are identical in intent across both tasks; signatures unchanged (`tmux-attention-picker` takes `pane_id`; `tmux-attention` takes `pane_id` + `marker`). Consistent.
