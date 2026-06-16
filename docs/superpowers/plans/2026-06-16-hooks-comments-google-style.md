# Hooks Comments + Google Shell Style + README — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring all 13 hooks and 5 libs in `claude/.claude/` to Google Shell Style Guide conformance with consistent header/section comments, and add a hooks README — without changing any behavior.

**Architecture:** Tooling-first, mechanical-then-semantic. A `shfmt` formatting pass (tool-verified, behavior-preserving) lands first, then hand-written comments and `main()` wrappers, then the README. A baseline-output harness guards the ~9 untested hooks against regressions.

**Tech Stack:** Bash, `shfmt`, `shellcheck` 0.11.0, the existing `tests/*/run.sh` suites, GNU Stow.

---

## Reference: locked decisions (from spec)

- Renaming: **functions/variables only, no files**.
- Comment depth: **header block + section comments**.
- README: **hooks + libs + test-running instructions**.
- Style: **full Google conformance incl. `shfmt`**.
- Shebang: **keep `#!/usr/bin/env bash`** (documented deviation from §2; macOS `/bin/bash` is 3.2, Homebrew bash 5 is outside `/bin`).
- `main()` (§7.7) applies only to scripts that define ≥1 function: **`notify.sh` and `read-once.sh`**. All other hooks are straight-line.

## Reference: file inventory

Hooks (`claude/.claude/hooks/`): `audit-log.sh`, `failure-recovery.sh`, `git-safety.sh`, `git-session-start.sh`, `notify.sh`, `permission-policy.sh`, `read-once-gc.sh`, `read-once.sh`, `resolve-pr-refs.sh`, `restore-git-context.sh`, `worktree-entered.sh`, `worktree-exited.sh`, `worktree-guard.sh`.

Libs (`claude/.claude/lib/`): `commit-scope.sh`, `permission-policy.sh`, `portability.sh`, `read-once-cache.sh`, `session.sh`.

Test suites (`claude/.claude/tests/`): `commit-scope/`, `permission-policy/`, `read-once/`, `session-lib/`.

## Reference: canonical header template

Every hook's top-of-file block is normalized to this shape. Preserve any
existing rich description prose below the field block — only restructure
the top into these fields. Do **not** repeat the shebang-deviation note
in each file; it lives once in the README.

```bash
#!/usr/bin/env bash
#
# <name>.sh — <one-line purpose>
#
# Event:   <SessionStart | UserPromptSubmit | PreToolUse | PostToolUse |
#           PostToolUseFailure | SessionEnd | PostCompact | Notification>
# Matcher: <tool matcher, or "n/a">
# Exit:    <contract, e.g. "0 = allow; 2 = block (stderr → Claude)">
# Async:   <yes — must never block | omit line if synchronous>
#
# <Existing 2-6 line description of what the hook does and why.>

set -euo pipefail
```

Libs use a file-header (no Event/Matcher) plus per-function §4.2 blocks:

```bash
# <name>.sh — <one-line role>. Sourced by <consumer>.

# <function purpose>.
# Globals:   <names read/written, or "none">
# Arguments: <$1, $2 …, or "none">
# Outputs:   <stdout/stderr, or "none">
# Returns:   <exit status meaning, or "none">
fn_name() { …
```

---

## Task 1: Add shfmt to Brewfile

**Files:**
- Modify: `Brewfile` (alphabetical insert in the `brew` section)

- [ ] **Step 1: Find the insertion point**

Run: `grep -n '^brew "s' Brewfile`
Expected: lists `brew "..."` entries starting with `s`; `shfmt` sorts after `shellcheck` and before `shellharden`/`starship`/etc. Insert to keep alphabetical order.

- [ ] **Step 2: Add the entry**

Add this line in correct alphabetical position among the `brew` entries:

```ruby
brew "shfmt"
```

- [ ] **Step 3: Install it**

Run: `brew bundle --file=Brewfile`
Expected: installs `shfmt`; exits 0.

- [ ] **Step 4: Verify**

Run: `shfmt --version`
Expected: prints a version (e.g. `v3.x.x`).

- [ ] **Step 5: Commit**

```bash
git add Brewfile
git commit -m "chore(brewfile): add shfmt formatter"
```

---

## Task 2: Capture behavior baseline

A regression oracle for the ~9 untested hooks. Runs each hook against a
fixed payload in a throwaway environment and records stdout + exit code.
Re-run after every later task and diff. The harness is throwaway — under
`/tmp`, never committed.

**Files:**
- Create: `/tmp/hooks-baseline/run-harness.sh` (not committed)

- [ ] **Step 1: Write the harness**

Create `/tmp/hooks-baseline/run-harness.sh`:

```bash
#!/usr/bin/env bash
# Behavior baseline harness for claude hooks. Not committed.
set -u
HOOKS="$1"          # path to claude/.claude/hooks
OUT="$2"            # output dir for captured results
mkdir -p "$OUT"

# Throwaway env so side-effecting hooks touch nothing real.
export HOME="$OUT/fakehome"
export XDG_RUNTIME_DIR="$OUT/xdg"
export CLAUDE_PROJECT_DIR="$OUT/fakehome/.claude"
mkdir -p "$HOME/.claude" "$XDG_RUNTIME_DIR"

run() { # name  payload-json
  local name="$1" payload="$2"
  local rc
  printf '%s' "$payload" | bash "$HOOKS/$name" >"$OUT/$name.out" 2>"$OUT/$name.err"
  rc=$?
  echo "$rc" >"$OUT/$name.rc"
}

CWD="$PWD"
run git-session-start.sh   "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$CWD\",\"session_id\":\"base1\"}"
run resolve-pr-refs.sh     "{\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"$CWD\",\"prompt\":\"hello\",\"session_id\":\"base1\"}"
run worktree-entered.sh    "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"EnterWorktree\",\"cwd\":\"$CWD\",\"session_id\":\"base1\"}"
run worktree-exited.sh     "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"ExitWorktree\",\"cwd\":\"$CWD\",\"session_id\":\"base1\"}"
run worktree-guard.sh      "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$CWD/x\"},\"cwd\":\"$CWD\",\"session_id\":\"base1\"}"
run permission-policy.sh   "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hi\"},\"cwd\":\"$CWD\"}"
run audit-log.sh           "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hi\"},\"cwd\":\"$CWD\",\"session_id\":\"base1\"}"
run failure-recovery.sh    "{\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_response\":{\"stderr\":\"boom\"},\"cwd\":\"$CWD\"}"
run read-once-gc.sh        "{\"hook_event_name\":\"SessionEnd\",\"cwd\":\"$CWD\",\"session_id\":\"base1\"}"
run restore-git-context.sh "{\"hook_event_name\":\"PostCompact\",\"cwd\":\"$CWD\",\"session_id\":\"base1\"}"
run notify.sh              "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"ExitPlanMode\",\"cwd\":\"$CWD\",\"session_id\":\"base1\"}"
echo "baseline written to $OUT"
```

- [ ] **Step 2: Capture the baseline from the committed (pre-change) hooks**

Run:
```bash
bash /tmp/hooks-baseline/run-harness.sh \
  "$PWD/claude/.claude/hooks" /tmp/hooks-baseline/before
```
Expected: prints `baseline written to /tmp/hooks-baseline/before`; one `.out`/`.err`/`.rc` per hook.

- [ ] **Step 3: Record the comparison command for later tasks**

After each subsequent task, re-run the harness into a fresh dir and diff:
```bash
bash /tmp/hooks-baseline/run-harness.sh \
  "$PWD/claude/.claude/hooks" /tmp/hooks-baseline/after
diff -r /tmp/hooks-baseline/before /tmp/hooks-baseline/after
```
Expected after every task: **no diff** (identical stdout + exit codes).
Note: `audit-log`/`read-once-gc` write under the fake `$HOME`; their
`.out`/`.rc` are what we compare — side-effect files live in the
throwaway home and are ignored by the diff (different subdir is fine as
long as `.out`/`.err`/`.rc` match; if `.err` carries timestamps, compare
`.out` + `.rc` only).

No commit (harness is not part of the repo).

---

## Task 3: Mechanical shfmt + shellcheck pass

Behavior-preserving formatting across all 18 files. No comments or
structure changes here.

**Files:**
- Modify: all 13 hooks + 5 libs (formatting only)

- [ ] **Step 1: Preview the format diff**

Run:
```bash
cd claude/.claude
shfmt -i 2 -ci -bn -d hooks/*.sh lib/*.sh
```
Expected: a diff showing 2-space indent / formatting normalizations. Review that it is purely formatting (no logic moved).

- [ ] **Step 2: Apply formatting**

Run:
```bash
cd claude/.claude
shfmt -i 2 -ci -bn -w hooks/*.sh lib/*.sh
```
Expected: files rewritten in place; exits 0.

- [ ] **Step 3: shellcheck all files**

Run:
```bash
cd claude/.claude
shellcheck hooks/*.sh lib/*.sh
```
Expected: clean. If findings appear, fix only behavior-neutral ones
(quote a variable, `[ ]`→`[[ ]]`, backticks→`$(...)`, add `local`). If a
finding would change behavior, leave it and note it for the README
"known deviations" — do not alter logic in this pass.

- [ ] **Step 4: Run all four test suites**

Run:
```bash
cd claude/.claude/tests
for d in commit-scope permission-policy read-once session-lib; do
  echo "=== $d ==="; (cd "$d" && bash run.sh) || echo "FAIL: $d"
done
```
Expected: every suite exits 0, no `FAIL:` line.

- [ ] **Step 5: Diff behavior baseline**

Run:
```bash
bash /tmp/hooks-baseline/run-harness.sh \
  "$PWD/claude/.claude/hooks" /tmp/hooks-baseline/after-fmt
diff /tmp/hooks-baseline/before /tmp/hooks-baseline/after-fmt \
  --exclude=fakehome --exclude=xdg
```
Expected: no diff on `.out`/`.err`/`.rc`.

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/hooks/*.sh claude/.claude/lib/*.sh
git commit -m "style(claude): shfmt-format hooks and libs"
```

---

## Task 4: Wrap notify hook in main()

Structural, behavior-preserving. §7.7 requires `main` for scripts that
define another function — `notify.sh` and `read-once.sh` both qualify by
the letter, but **read-once.sh is exempted by decision**: it is the
hot-path hook (fires on every Read/Bash/Grep) with a deliberate
fast-exit-before-source structure (header lines 66-68); hoisting its
140-line `_check_path` above that boundary adds behavior risk for
marginal readability gain. read-once.sh keeps its flow structure and
documents the §7.7 deviation in its header (Task 6) and the README
(Task 9), alongside the env-bash deviation.

**Files:**
- Modify: `claude/.claude/hooks/notify.sh` (hoist `send_osc777` above a
  new `main()`; body vars stay global so behavior is identical)

- [ ] **Step 1: Wrap notify.sh top-level code in main()**

After the existing function definition(s) and any sourced libs/constants,
move the top-level execution body into a `main` function and call it at
the end. Pattern:

```bash
# (existing helper function definitions stay above)

# Entry point: dispatch on hook_event_name, emit notification.
# Globals:   reads stdin (hook JSON), TMUX, env notify settings
# Arguments: none
# Outputs:   OSC 777 escape / tmux bell; never blocks
# Returns:   always 0 (async hook must not fail Claude Code)
main() {
  # ← existing top-level body verbatim, indented one level
}

main "$@"
```

Preserve the body exactly; only indent it and add the `main`/call.

- [ ] **Step 2: Re-format notify.sh (indentation changed)**

Run:
```bash
cd claude/.claude
shfmt -i 2 -ci -bn -w hooks/notify.sh
shellcheck --severity=warning hooks/notify.sh
```
Expected: shfmt rewrites cleanly; shellcheck clean at warning+ severity.

- [ ] **Step 3: Baseline diff**

Run:
```bash
bash /tmp/hooks-baseline/run-harness.sh \
  "$PWD/claude/.claude/hooks" /tmp/hooks-baseline/after-main "$PWD"
diff /tmp/hooks-baseline/before/notify.sh.out /tmp/hooks-baseline/after-main/notify.sh.out
```
Expected: no `.out`/`.err`/`.rc` diff for `notify.sh`.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/hooks/notify.sh
git commit -m "refactor(claude): wrap notify hook body in main()"
```

---

## Task 5: Normalize header + section comments — group A (non-PreToolUse hooks)

Apply the canonical header template. Most of these already carry the
described prose — restructure the top into the `Event/Matcher/Exit/Async`
field block and add section comments to any uncommented logical block.

**Files (with the exact field block to ensure at top):**

- Modify: `claude/.claude/hooks/git-session-start.sh`
  ```
  # git-session-start.sh — inject git/worktree context at session start.
  #
  # Event:   SessionStart
  # Matcher: n/a
  # Exit:    0 always (emits additionalContext + systemMessage JSON)
  ```
- Modify: `claude/.claude/hooks/resolve-pr-refs.sh`
  ```
  # resolve-pr-refs.sh — inject prompt-driven context; clear stale
  #                      attention markers.
  #
  # Event:   UserPromptSubmit
  # Matcher: n/a
  # Exit:    0 always. Fast path (<10ms) on no match.
  ```
- Modify: `claude/.claude/hooks/failure-recovery.sh`
  ```
  # failure-recovery.sh — inject targeted recovery guidance when a tool
  #                       call fails.
  #
  # Event:   PostToolUseFailure
  # Matcher: n/a
  # Exit:    0 always. Fast exit for unrecognized failures.
  ```
- Modify: `claude/.claude/hooks/read-once-gc.sh`
  ```
  # read-once-gc.sh — prune the ended session's read-once cache + orphan
  #                   snapshot dirs.
  #
  # Event:   SessionEnd
  # Matcher: n/a
  # Exit:    0 always (best-effort; no `set -e`). Opt-out: READ_ONCE_GC_DISABLE=1
  ```
- Modify: `claude/.claude/hooks/restore-git-context.sh`
  ```
  # restore-git-context.sh — re-inject git/worktree context after a
  #                          compaction drops it.
  #
  # Event:   PostCompact
  # Matcher: n/a
  # Exit:    0 always (emits context JSON; silent if not in a git repo)
  ```

- [ ] **Step 1: Edit each of the 5 files**

For each file: replace the existing top comment block with the field
block above (keep the file's existing longer description prose beneath
it), and add a one-line `# --- <section> ---` comment before each
logical block that lacks one. Do not touch executable logic.

- [ ] **Step 2: shfmt + shellcheck the group**

Run:
```bash
cd claude/.claude
shfmt -i 2 -ci -bn -w hooks/git-session-start.sh hooks/resolve-pr-refs.sh \
  hooks/failure-recovery.sh hooks/read-once-gc.sh hooks/restore-git-context.sh
shellcheck hooks/git-session-start.sh hooks/resolve-pr-refs.sh \
  hooks/failure-recovery.sh hooks/read-once-gc.sh hooks/restore-git-context.sh
```
Expected: clean.

- [ ] **Step 3: Baseline diff**

Run:
```bash
bash /tmp/hooks-baseline/run-harness.sh \
  "$PWD/claude/.claude/hooks" /tmp/hooks-baseline/after-groupA
diff /tmp/hooks-baseline/before /tmp/hooks-baseline/after-groupA \
  --exclude=fakehome --exclude=xdg
```
Expected: no `.out`/`.err`/`.rc` diff.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/hooks/git-session-start.sh \
  claude/.claude/hooks/resolve-pr-refs.sh \
  claude/.claude/hooks/failure-recovery.sh \
  claude/.claude/hooks/read-once-gc.sh \
  claude/.claude/hooks/restore-git-context.sh
git commit -m "docs(claude): normalize comments for session/failure/compact hooks"
```

---

## Task 6: Normalize header + section comments — group B (PreToolUse hooks)

**Files (exact field block to ensure at top):**

- Modify: `claude/.claude/hooks/read-once.sh`
  ```
  # read-once.sh — block redundant reads already in this session's context.
  #
  # Event:   PreToolUse
  # Matcher: Read|NotebookRead|mcp__qmd__get|Bash|Grep
  # Exit:    0 = allow (record fresh entry); 2 = block (stderr → Claude)
  ```
- Modify: `claude/.claude/hooks/git-safety.sh`
  ```
  # git-safety.sh — guard git Bash calls: main-branch + commit-scope/atomicity.
  #
  # Event:   PreToolUse
  # Matcher: Bash
  # Exit:    0 = allow (warnings → stdout); 2 = block (stderr → Claude)
  ```
- Modify: `claude/.claude/hooks/worktree-guard.sh`
  ```
  # worktree-guard.sh — block file edits until EnterWorktree() this session.
  #
  # Event:   PreToolUse
  # Matcher: Write|Edit|NotebookEdit
  # Exit:    0 = allow; 2 = block (stderr → Claude)
  ```
- Modify: `claude/.claude/hooks/permission-policy.sh`
  ```
  # permission-policy.sh — semantic permission policy; dispatch by tool_name.
  #
  # Event:   PreToolUse
  # Matcher: Bash|Write|Edit|NotebookEdit|WebFetch
  # Exit:    0 = allow/ask-emitted (never deny). Off: CLAUDE_PERMISSION_POLICY=off
  ```

- [ ] **Step 1: Edit each of the 4 files**

Apply the field block (preserve existing prose beneath, e.g. read-once's
long cache description) and add `# --- <section> ---` markers to any
uncommented block. No logic changes. `read-once.sh` already has its
`main()` from Task 4 — only its header/sections change here.

- [ ] **Step 2: shfmt + shellcheck the group**

Run:
```bash
cd claude/.claude
shfmt -i 2 -ci -bn -w hooks/read-once.sh hooks/git-safety.sh \
  hooks/worktree-guard.sh hooks/permission-policy.sh
shellcheck hooks/read-once.sh hooks/git-safety.sh \
  hooks/worktree-guard.sh hooks/permission-policy.sh
```
Expected: clean.

- [ ] **Step 3: Run git-safety + read-once + permission-policy suites**

Run:
```bash
cd claude/.claude/tests
for d in commit-scope read-once permission-policy; do
  echo "=== $d ==="; (cd "$d" && bash run.sh) || echo "FAIL: $d"
done
```
Expected: all exit 0, no `FAIL:`.

- [ ] **Step 4: Baseline diff**

Run:
```bash
bash /tmp/hooks-baseline/run-harness.sh \
  "$PWD/claude/.claude/hooks" /tmp/hooks-baseline/after-groupB
diff /tmp/hooks-baseline/before /tmp/hooks-baseline/after-groupB \
  --exclude=fakehome --exclude=xdg
```
Expected: no `.out`/`.err`/`.rc` diff.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/hooks/read-once.sh claude/.claude/hooks/git-safety.sh \
  claude/.claude/hooks/worktree-guard.sh claude/.claude/hooks/permission-policy.sh
git commit -m "docs(claude): normalize comments for PreToolUse hooks"
```

---

## Task 7: Normalize header + section comments — group C (PostToolUse + Notification hooks)

**Files (exact field block to ensure at top):**

- Modify: `claude/.claude/hooks/worktree-entered.sh`
  ```
  # worktree-entered.sh — clear pending state once a worktree is entered.
  #
  # Event:   PostToolUse
  # Matcher: EnterWorktree
  # Exit:    0 always (PostToolUse must not block; emits context JSON)
  ```
- Modify: `claude/.claude/hooks/worktree-exited.sh`
  ```
  # worktree-exited.sh — remind Claude of next steps after leaving a worktree.
  #
  # Event:   PostToolUse
  # Matcher: ExitWorktree
  # Exit:    0 always (PostToolUse must not block; emits context JSON)
  ```
- Modify: `claude/.claude/hooks/audit-log.sh`
  ```
  # audit-log.sh — append a JSONL audit entry for every mutating tool call.
  #
  # Event:   PostToolUse
  # Matcher: Bash|Write|Edit|NotebookEdit|CronCreate|CronDelete|RemoteTrigger|Read|NotebookRead|Grep|mcp__qmd__get|mcp__qmd__multi_get
  # Exit:    0 always.
  # Async:   yes — must never block Claude Code.
  ```
- Modify: `claude/.claude/hooks/notify.sh`
  ```
  # notify.sh — alert the user (Ghostty OSC 777 + tmux bell) on attention.
  #
  # Event:   PreToolUse (AskUserQuestion|ExitPlanMode) and Notification
  # Matcher: AskUserQuestion|ExitPlanMode (+ Notification event)
  # Exit:    0 always.
  # Async:   yes — must never block Claude Code.
  ```

- [ ] **Step 1: Edit each of the 4 files**

Apply the field block (preserve existing prose). `notify.sh` already has
its `main()` from Task 4 — only header/sections change here. Confirm the
`audit-log.sh` and `notify.sh` matchers against `settings.base.json`
before writing them (authoritative source).

Run (to confirm matchers):
```bash
grep -n -A6 'audit-log.sh\|notify.sh' claude/.claude/settings.base.json
```

- [ ] **Step 2: shfmt + shellcheck the group**

Run:
```bash
cd claude/.claude
shfmt -i 2 -ci -bn -w hooks/worktree-entered.sh hooks/worktree-exited.sh \
  hooks/audit-log.sh hooks/notify.sh
shellcheck hooks/worktree-entered.sh hooks/worktree-exited.sh \
  hooks/audit-log.sh hooks/notify.sh
```
Expected: clean.

- [ ] **Step 3: Baseline diff**

Run:
```bash
bash /tmp/hooks-baseline/run-harness.sh \
  "$PWD/claude/.claude/hooks" /tmp/hooks-baseline/after-groupC
diff /tmp/hooks-baseline/before /tmp/hooks-baseline/after-groupC \
  --exclude=fakehome --exclude=xdg
```
Expected: no `.out`/`.err`/`.rc` diff.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/hooks/worktree-entered.sh \
  claude/.claude/hooks/worktree-exited.sh \
  claude/.claude/hooks/audit-log.sh claude/.claude/hooks/notify.sh
git commit -m "docs(claude): normalize comments for PostToolUse/notify hooks"
```

---

## Task 8: Add function comment blocks to libs

Apply the §4.2 file-header + per-function block format to all 5 libs.
Keep existing function names and prefixes (`rc_`, `emit_`, `_repo_basename`).

**Files:**
- Modify: `claude/.claude/lib/commit-scope.sh` (functions: `_repo_basename`, `_known_scopes`, `_is_container`, `_in_known_scopes`, `_seg_matches_scope`, `_path_segments`, `is_banned_scope`, `suggest_scope`)
- Modify: `claude/.claude/lib/permission-policy.sh` (functions: `check_bash`, `check_file_edit`, `check_web_fetch`)
- Modify: `claude/.claude/lib/portability.sh` (functions: `file_mtime`, `run_timeout`)
- Modify: `claude/.claude/lib/read-once-cache.sh` (functions: `rc_record`, `rc_lookup`, `rc_deny`, `rc_recent_touch`, `rc_path_slug`)
- Modify: `claude/.claude/lib/session.sh` (functions: `emit_context`, `emit_context_with_msg`, `parse_session_id`, `pending_file`, `check_worktree_pending`, `cwd_repo_hint`, `worktree_kind`, `workflow_no_pr`)

- [ ] **Step 1: Add a file-header to each lib**

One-line role + who sources it, e.g.:
```bash
# commit-scope.sh — commit-scope signal validation (S1-S4). Sourced by
#                   hooks/git-safety.sh and tests/commit-scope.
```
Use: `permission-policy.sh` → "pattern matchers for the permission-policy hook"; `portability.sh` → "cross-platform helpers (mtime, timeout)"; `read-once-cache.sh` → "read-once cache record/lookup/deny helpers"; `session.sh` → "session-id parsing, context emit, worktree/workflow helpers".

- [ ] **Step 2: Add a §4.2 block above each function**

For every function listed above, add the block:
```bash
# <what it does>.
# Globals:   <read/written globals, or "none">
# Arguments: <$1 …, or "none">
# Outputs:   <stdout/stderr, or "none">
# Returns:   <status meaning, or "none">
```
Read each function body to fill the fields accurately. No logic changes.

- [ ] **Step 3: shfmt + shellcheck the libs**

Run:
```bash
cd claude/.claude
shfmt -i 2 -ci -bn -w lib/*.sh
shellcheck lib/*.sh
```
Expected: clean.

- [ ] **Step 4: Run all four suites (libs back every suite)**

Run:
```bash
cd claude/.claude/tests
for d in commit-scope permission-policy read-once session-lib; do
  echo "=== $d ==="; (cd "$d" && bash run.sh) || echo "FAIL: $d"
done
```
Expected: all exit 0, no `FAIL:`.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/lib/*.sh
git commit -m "docs(claude): add function comment blocks to hook libs"
```

---

## Task 9: Write the hooks README

**Files:**
- Create: `claude/.claude/hooks/README.md`

- [ ] **Step 1: Confirm authoritative registration data**

Run:
```bash
grep -n -B1 -A4 'hooks/.*\.sh' claude/.claude/settings.base.json
cat ~/workspace/claude-skills/settings.overlay.json 2>/dev/null | grep -n 'hooks/' || echo 'no overlay hook regs'
```
Expected: the event/matcher for each hook. Use these to fill the tables —
do not rely on memory.

- [ ] **Step 2: Write the README**

Create `claude/.claude/hooks/README.md` with this structure and content
(fill the one-line purposes from the hook headers written in Tasks 5-7):

````markdown
# Claude Code Hooks

Shell hooks that fire on Claude Code lifecycle and tool events. Registered
in `claude/.claude/settings.base.json` under `hooks` (merged with the work
overlay by `claude-sync` into `~/.claude/settings.json`). All hooks are
stowed to `~/.claude/hooks/` and invoked as `bash $HOME/.claude/hooks/<name>.sh`.

## Conventions

- **Shebang:** every hook uses `#!/usr/bin/env bash`. This deviates from
  Google Shell Style Guide §2 (`#!/bin/bash`) on purpose: macOS ships
  bash 3.2 at `/bin/bash`, while Homebrew bash 5 lives outside `/bin`.
  `env bash` selects the modern bash on both macOS and Linux.
- **Exit codes:** PreToolUse hooks use `exit 0` = allow, `exit 2` = block
  (stderr is shown to Claude). PostToolUse/SessionStart/etc. emit
  structured JSON (`additionalContext`, `systemMessage`,
  `permissionDecision`) and should not block.
- **Async hooks** (`audit-log.sh`, `notify.sh`) must never slow Claude.
- **Style:** files conform to the Google Shell Style Guide, formatted
  with `shfmt -i 2 -ci -bn` and linted with `shellcheck`.

## Hooks by event

### SessionStart
| Hook | Purpose | Exit |
| --- | --- | --- |
| `git-session-start.sh` | inject git/worktree context at session start | 0 |

### UserPromptSubmit
| Hook | Purpose | Exit |
| --- | --- | --- |
| `resolve-pr-refs.sh` | inject prompt-driven context; clear attention markers | 0 |

### PreToolUse
| Hook | Matcher | Purpose | Exit |
| --- | --- | --- | --- |
| `read-once.sh` | `Read\|NotebookRead\|mcp__qmd__get\|Bash\|Grep` | block redundant reads already in context | 0 allow / 2 block |
| `git-safety.sh` | `Bash` | main-branch + commit-scope/atomicity guard | 0 allow / 2 block |
| `worktree-guard.sh` | `Write\|Edit\|NotebookEdit` | block edits until EnterWorktree() | 0 allow / 2 block |
| `permission-policy.sh` | `Bash\|Write\|Edit\|NotebookEdit\|WebFetch` | semantic permission policy (emits ask) | 0 |
| `notify.sh` | `AskUserQuestion\|ExitPlanMode` | attention notification (async) | 0 |

### PostToolUse
| Hook | Matcher | Purpose | Exit |
| --- | --- | --- | --- |
| `worktree-entered.sh` | `EnterWorktree` | clear pending state on entry | 0 |
| `worktree-exited.sh` | `ExitWorktree` | remind of post-worktree steps | 0 |
| `audit-log.sh` | mutating + read tools | append JSONL audit entry (async) | 0 |

### PostToolUseFailure
| Hook | Purpose | Exit |
| --- | --- | --- |
| `failure-recovery.sh` | inject recovery guidance on tool failure | 0 |

### SessionEnd
| Hook | Purpose | Exit |
| --- | --- | --- |
| `read-once-gc.sh` | prune ended session's read-once cache | 0 |

### PostCompact
| Hook | Purpose | Exit |
| --- | --- | --- |
| `restore-git-context.sh` | re-inject git context after compaction | 0 |

### Notification
| Hook | Purpose | Exit |
| --- | --- | --- |
| `notify.sh` | attention notification (also on PreToolUse) | 0 |

## Shared libraries (`../lib/`)

Hooks source these via `../lib/<name>.sh`. Verify the actual matchers and
registrations in `settings.base.json` — the tables above are documentation,
not the source of truth.

| Lib | Role | Key functions |
| --- | --- | --- |
| `session.sh` | session id, context emit, worktree/workflow helpers | `emit_context`, `parse_session_id`, `check_worktree_pending`, `worktree_kind`, `workflow_no_pr` |
| `commit-scope.sh` | commit-scope signal validation (S1-S4) | `is_banned_scope`, `suggest_scope` |
| `permission-policy.sh` | permission-policy pattern matchers | `check_bash`, `check_file_edit`, `check_web_fetch` |
| `read-once-cache.sh` | read-once cache helpers | `rc_record`, `rc_lookup`, `rc_deny` |
| `portability.sh` | cross-platform mtime/timeout | `file_mtime`, `run_timeout` |

## Tests (`../tests/`)

Each suite iterates `cases/*.sh` and exits non-zero on any failure:

```sh
cd claude/.claude/tests/<suite> && bash run.sh
```

| Suite | Covers |
| --- | --- |
| `commit-scope/` | `lib/commit-scope.sh` + `git-safety.sh` commit-scope logic |
| `permission-policy/` | `lib/permission-policy.sh` + `permission-policy.sh` hook |
| `read-once/` | `read-once.sh` hook + `lib/read-once-cache.sh` |
| `session-lib/` | `lib/session.sh` |

Hooks without a dedicated suite (`audit-log`, `failure-recovery`,
`git-session-start`, `notify`, `resolve-pr-refs`, `restore-git-context`,
`read-once-gc`, `worktree-entered`, `worktree-exited`) are verified by
`shellcheck` and manual smoke runs.
````

- [ ] **Step 3: Lint the README is not a shell file (sanity only)**

Run: `test -f claude/.claude/hooks/README.md && echo OK`
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/hooks/README.md
git commit -m "docs(claude): add hooks README"
```

---

## Task 10: Final verification

- [ ] **Step 1: shfmt reports zero diff everywhere**

Run:
```bash
cd claude/.claude
shfmt -i 2 -ci -bn -d hooks/*.sh lib/*.sh
```
Expected: no output (zero diff).

- [ ] **Step 2: shellcheck clean everywhere**

Run:
```bash
cd claude/.claude
shellcheck hooks/*.sh lib/*.sh
```
Expected: no output.

- [ ] **Step 3: All suites green**

Run:
```bash
cd claude/.claude/tests
for d in commit-scope permission-policy read-once session-lib; do
  echo "=== $d ==="; (cd "$d" && bash run.sh) || echo "FAIL: $d"
done
```
Expected: all exit 0, no `FAIL:`.

- [ ] **Step 4: Final behavior baseline diff**

Run:
```bash
bash /tmp/hooks-baseline/run-harness.sh \
  "$PWD/claude/.claude/hooks" /tmp/hooks-baseline/after-final
diff /tmp/hooks-baseline/before /tmp/hooks-baseline/after-final \
  --exclude=fakehome --exclude=xdg
```
Expected: no `.out`/`.err`/`.rc` diff vs. the original committed hooks.

- [ ] **Step 5: Stow re-link sanity**

Run:
```bash
cd ~/workspace/dotfiles && stow -t ~ -R claude && \
  ls -l ~/.claude/hooks/README.md ~/.claude/hooks/git-safety.sh
```
Expected: symlinks resolve into the repo; no stow conflict errors.

- [ ] **Step 6: Confirm every header field is present**

Run:
```bash
cd claude/.claude/hooks
for f in *.sh; do grep -q '^# Event:' "$f" || echo "MISSING header: $f"; done
```
Expected: no `MISSING header:` line.

---

## Self-review notes

- **Spec coverage:** Brewfile+shfmt (T1,T3), comments all hooks (T5-7),
  comments all libs (T8), `main()` where required (T4), README incl.
  libs+tests (T9), `env bash` deviation documented (T9 README), full
  verification incl. `shfmt -d`/shellcheck/suites/stow (T10). All spec
  steps mapped.
- **No file renames** anywhere (spec non-goal honored).
- **Commit scopes:** `brewfile` for the Brewfile, `claude` for all hook/
  lib/README work (matches `git log` history; avoids S3 `hooks` trap).
- **Behavior preservation:** baseline harness (T2) diffed after every
  task; suites + shellcheck + `shfmt -d` as additional oracles.
