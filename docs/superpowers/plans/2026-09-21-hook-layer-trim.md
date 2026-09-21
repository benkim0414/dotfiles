# Hook Layer Trim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the Claude Code hook layer from 14 registrations and 2,443 lines to 4 registrations and ~650 lines, keeping only worktree isolation, atomic commits, and conventional commit scope.

**Architecture:** Worktree isolation stays a three-part mechanism -- a SessionStart hook arms a marker file, a PreToolUse hook blocks edits while it exists, a PostToolUse hook clears it on `EnterWorktree`. The 169-line `git-session-start.sh` is replaced by a ~30-line `arm-worktree-guard.sh` that does only the arming. `git-safety.sh` is renamed `commit-guard.sh` and loses its `no-pr` mode gates. Everything else in the hook layer is deleted, along with the `tmux-attention` component whose only producer was one of the deleted hooks.

**Tech Stack:** bash 3.2 (macOS `/bin/bash` 3.2.57 -- hook registrations name the interpreter, so shebangs are never consulted), `jq`, GNU Stow, Claude Code hook JSON protocol.

**Spec:** `docs/superpowers/specs/2026-09-21-hook-layer-trim-design.md`

## Global Constraints

- **bash 3.2 only.** No `${x,,}`, no `declare -A`, no `mapfile`, no namerefs. Bash 4 syntax fails *silently* here. Lowercase via `to_lower` from `claude/.claude/lib/portability.sh`.
- **Test hooks the way the config invokes them:** `bash <path>`, or `/bin/bash <path>` explicitly. A green run under Homebrew bash 5 proves nothing.
- **Exit codes:** PreToolUse `exit 0` = allow, `exit 2` = block (stderr shown to Claude). PostToolUse / SessionStart must never block.
- **Style:** Google Shell Style Guide, `shfmt -i 2 -ci -bn`, `shellcheck --severity=warning`. Shebang is `#!/usr/bin/env bash` (documented deviation).
- **Stage explicit paths.** `git add <path>`. Never `-A`, `.`, `--all`, `--update`, `git commit -a`, `git commit -am`.
- **One commit per task.** Conventional form `type(scope): description`; scope names a component, not a directory. Known scopes here: `claude`, `zsh`, `herdr`, `codex`, `tmux-attention`, `atuin`.
- **Never run `stow` or `claude-sync` from the worktree.** Both are post-merge steps from the main checkout. See "After Merge" at the end.
- **The worktree-isolation guard refuses `for` loops and heredocs in Bash calls.** Run each test suite as its own plain command.

## File Structure

| Path | Responsibility | Task |
| --- | --- | --- |
| `claude/.claude/tests/worktree-guard/` | characterize the block/allow branches of the guard | 1 |
| `claude/.claude/hooks/arm-worktree-guard.sh` | write the pending marker at SessionStart | 2 |
| `claude/.claude/tests/arm-worktree-guard/` | prove the marker is actually written | 2 |
| `claude/.claude/hooks/git-safety.sh` | lose `no-pr` gates, then become `commit-guard.sh` | 3, 4 |
| `claude/.claude/lib/session.sh` | lose `workflow_no_pr` | 5 |
| `claude/.claude/lib/portability.sh` | lose `run_timeout` | 5 |
| `claude/.claude/settings.base.json` | 14 registrations -> 4 | 4, 6 |
| 12 hooks and libs | deleted | 6 |
| `bin/.local/bin/tmux-attention*`, `tmux/.config/tmux/tmux.conf` | retire the component | 7 |
| `claude/.claude/hooks/README.md`, `CLAUDE.md` | documentation | 8 |

---

### Task 1: Characterization suite for `worktree-guard.sh`

The guard has no test today. It is the highest-risk file in the change: its failure mode is silent permissiveness, and every later task edits the registration that invokes it. This suite is the regression baseline for tasks 2-6.

These are characterization tests -- the code already exists, so they pass on first run. That is exactly the shape the repo warns about in `docs/solutions/conventions/assertions-that-pass-when-they-cannot-check-2026-09-18.md`, so step 5 deliberately breaks the guard and confirms the suite goes red before accepting it.

**Files:**
- Create: `claude/.claude/tests/worktree-guard/run.sh`
- Create: `claude/.claude/tests/worktree-guard/helpers.sh`
- Create: `claude/.claude/tests/worktree-guard/cases/00-no-marker-allows.sh`
- Create: `claude/.claude/tests/worktree-guard/cases/10-marker-blocks-repo-file.sh`
- Create: `claude/.claude/tests/worktree-guard/cases/20-marker-allows-outside-repo.sh`
- Create: `claude/.claude/tests/worktree-guard/cases/30-linked-worktree-self-heals.sh`
- Create: `claude/.claude/tests/worktree-guard/cases/40-no-session-id-allows.sh`

**Interfaces:**
- Consumes: `claude/.claude/hooks/worktree-guard.sh` (unchanged), `claude/.claude/lib/session.sh` (unchanged).
- Produces: `run.sh` exiting 0 on success / 1 on any failure, matching `commit-scope/run.sh`. Task 6 adds this suite to the verification sweep.

**Key facts the implementer needs:**
- `worktree-guard.sh:14` hardcodes `STATE_DIR="$HOME/.claude/session-worktrees"`, and `lib/session.sh:54` sets the same at source time. Tests **must** override `HOME` to a temp directory before invoking the hook, or they will read and delete the real markers of live sessions.
- `parse_session_id` (`lib/session.sh:44`) accepts a value only if it matches `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`. Test payloads need a real-shaped UUID.
- The payload key is top-level `session_id`; the path keys are `tool_input.file_path`, `.path`, `.notebook_path`.

- [ ] **Step 1: Write the runner**

Create `claude/.claude/tests/worktree-guard/run.sh`:

```bash
#!/usr/bin/env bash
# worktree-guard hook test runner.
# Iterates cases/*.sh; each case sources helpers.sh.
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_HOME="$HERE"
export LIB="$HERE/../../lib/session.sh"
export HOOK="$HERE/../../hooks/worktree-guard.sh"

[[ -f "$LIB"  ]] || { echo "missing lib: $LIB"   >&2; exit 2; }
[[ -f "$HOOK" ]] || { echo "missing hook: $HOOK" >&2; exit 2; }

pass=0; fail=0; failed_cases=()
for case in "$HERE"/cases/*.sh; do
  [[ -e "$case" ]] || continue
  name="$(basename "$case" .sh)"
  if ( cd "$HERE" && bash "$case" ); then
    printf "  PASS  %s\n" "$name"
    pass=$((pass+1))
  else
    printf "  FAIL  %s\n" "$name"
    fail=$((fail+1))
    failed_cases+=("$name")
  fi
done

printf "\n%d passed, %d failed\n" "$pass" "$fail"
if (( fail > 0 )); then
  printf "failed cases: %s\n" "${failed_cases[*]}"
  exit 1
fi
```

- [ ] **Step 2: Write the helpers**

Create `claude/.claude/tests/worktree-guard/helpers.sh`:

```bash
#!/usr/bin/env bash
# Sourced by every case. Provides a sandboxed HOME, git fixtures, and
# assertions for the worktree guard.
set -uo pipefail

: "${HOOK:?HOOK must be set by run.sh}"

# Resolve to the physical path: on macOS mktemp lives under /var -> /private/var.
# `git rev-parse --absolute-git-dir` resolves symlinks but `cd <dir> && pwd`
# does not, so an unresolved fixture path makes the guard read a main checkout
# as a linked worktree and allow the edit. Same convention, same reason, as
# claude/.claude/tests/session-lib/helpers.sh:12.
CASE_TMP="$(cd "$(mktemp -d -t worktree-guard-test.XXXXXX)" && pwd -P)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# Sandbox HOME so the hook never touches the real ~/.claude/session-worktrees.
export HOME="$CASE_TMP/home"
export STATE_DIR="$HOME/.claude/session-worktrees"
mkdir -p "$STATE_DIR"

# A valid-shaped session id; parse_session_id rejects anything else.
SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

# make_repo <dir>
# Creates a git repo with one commit so HEAD is valid.
make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  ( cd "$dir" \
    && git init -q -b feature \
    && git config user.email "test@example.com" \
    && git config user.name "Test" \
    && git config core.hooksPath /dev/null \
    && git commit -q --allow-empty -m "chore(seed): initial" )
}

# add_linked_worktree <repo-dir> <name>
# Creates <repo-dir>/.claude/worktrees/<name> on a new branch and echoes its path.
add_linked_worktree() {
  local dir="$1" name="$2"
  ( cd "$dir" && git worktree add -q -b "wt-$name" ".claude/worktrees/$name" >/dev/null 2>&1 )
  printf '%s' "$dir/.claude/worktrees/$name"
}

set_marker()   { touch "$STATE_DIR/pending-$SID"; }
clear_marker() { rm -f "$STATE_DIR/pending-$SID"; }
marker_exists() { [[ -f "$STATE_DIR/pending-$SID" ]]; }

# guard_json <file_path> [session_id]
# Emits a PreToolUse Write payload.
guard_json() {
  local path="$1" sid="${2:-$SID}"
  jq -cn --arg p "$path" --arg s "$sid" \
    '{session_id:$s, tool_name:"Write", tool_input:{file_path:$p}}'
}

# guard_json_no_sid <file_path>
guard_json_no_sid() {
  jq -cn --arg p "$1" '{tool_name:"Write", tool_input:{file_path:$p}}'
}

# run_guard_status <cwd> <json>
# Runs the hook from <cwd> with the given payload; echoes the exit status.
run_guard_status() {
  local dir="$1" json="$2"
  ( cd "$dir" && printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1; echo $? )
}

assert_status() {
  local want="$1" got="$2" what="$3"
  [[ "$got" == "$want" ]] \
    || { echo "  $what: want exit=$want got exit=$got" >&2; exit 1; }
}
```

- [ ] **Step 3: Write the five cases**

`cases/00-no-marker-allows.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
clear_marker

status=$(run_guard_status "$repo" "$(guard_json "$repo/src/a.txt")")
assert_status 0 "$status" "no marker must allow"
```

`cases/10-marker-blocks-repo-file.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# THE decisive case. If this passes against a deleted or neutered guard,
# the whole suite is worthless. See step 5 of Task 1.
repo="$CASE_TMP/repo"
make_repo "$repo"
set_marker

status=$(run_guard_status "$repo" "$(guard_json "$repo/src/a.txt")")
assert_status 2 "$status" "marker + in-repo path must block"
```

`cases/20-marker-allows-outside-repo.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
set_marker

outside="$CASE_TMP/scratch/note.md"
status=$(run_guard_status "$repo" "$(guard_json "$outside")")
assert_status 0 "$status" "path outside the working tree must be allowed"
```

`cases/30-linked-worktree-self-heals.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
wt="$(add_linked_worktree "$repo" feat)"
set_marker

status=$(run_guard_status "$wt" "$(guard_json "$wt/src/a.txt")")
assert_status 0 "$status" "edits inside a linked worktree must be allowed"

if marker_exists; then
  echo "  stale marker was not cleared by the self-healing branch" >&2
  exit 1
fi
```

`cases/40-no-session-id-allows.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
set_marker

status=$(run_guard_status "$repo" "$(guard_json_no_sid "$repo/src/a.txt")")
assert_status 0 "$status" "a payload with no session_id must not block"
```

- [ ] **Step 4: Run the suite and verify it passes**

```bash
cd claude/.claude/tests/worktree-guard && bash run.sh
```

Expected: `5 passed, 0 failed`.

If `30-linked-worktree-self-heals` fails, check that `git worktree add` succeeded -- `add_linked_worktree` swallows its output. Re-run that command without `>/dev/null 2>&1` to see the error.

- [ ] **Step 5: Prove the suite can fail (red-green)**

A passing characterization suite proves nothing until you have seen it go red. Temporarily neuter the guard's block:

```bash
cp claude/.claude/hooks/worktree-guard.sh /tmp/worktree-guard.bak
printf '#!/usr/bin/env bash\nexit 0\n' > claude/.claude/hooks/worktree-guard.sh
cd claude/.claude/tests/worktree-guard && bash run.sh
```

Expected: `3 passed, 2 failed`, with
`failed cases: 10-marker-blocks-repo-file 30-linked-worktree-self-heals`.

Two cases go red, not one, because a bare `exit 0` removes two distinct
behaviours: case 10 loses the block, and case 30 loses the self-healing
marker deletion that its second assertion checks. Both are real properties
of the guard, so two failures is the stronger signal.

If all five still pass, the suite is not testing the guard -- stop and fix it
before restoring.

Restore:

```bash
cp /tmp/worktree-guard.bak claude/.claude/hooks/worktree-guard.sh
cd claude/.claude/tests/worktree-guard && bash run.sh
```

Expected: `5 passed, 0 failed`.

- [ ] **Step 6: Lint**

```bash
shellcheck --severity=warning claude/.claude/tests/worktree-guard/run.sh claude/.claude/tests/worktree-guard/helpers.sh
shfmt -i 2 -ci -bn -l claude/.claude/tests/worktree-guard/
```

`shfmt -l` must print nothing. If it lists files, run the same command with `-w` to fix them, then re-run the suite.

- [ ] **Step 7: Commit**

```bash
git add claude/.claude/tests/worktree-guard/run.sh \
        claude/.claude/tests/worktree-guard/helpers.sh \
        claude/.claude/tests/worktree-guard/cases/00-no-marker-allows.sh \
        claude/.claude/tests/worktree-guard/cases/10-marker-blocks-repo-file.sh \
        claude/.claude/tests/worktree-guard/cases/20-marker-allows-outside-repo.sh \
        claude/.claude/tests/worktree-guard/cases/30-linked-worktree-self-heals.sh \
        claude/.claude/tests/worktree-guard/cases/40-no-session-id-allows.sh
git commit -m "test(claude): characterize the worktree guard's block and allow branches"
```

---

### Task 2: Extract `arm-worktree-guard.sh` from `git-session-start.sh`

`git-session-start.sh:157` is the only writer of the pending marker anywhere in the tree, and nothing asserts that. Task 6 deletes that file; this task moves the arming into a hook that does nothing else, and tests the coupling first.

**Files:**
- Create: `claude/.claude/hooks/arm-worktree-guard.sh`
- Create: `claude/.claude/tests/arm-worktree-guard/run.sh`
- Create: `claude/.claude/tests/arm-worktree-guard/helpers.sh`
- Create: `claude/.claude/tests/arm-worktree-guard/cases/00-arms-in-main-checkout.sh`
- Create: `claude/.claude/tests/arm-worktree-guard/cases/10-skips-in-linked-worktree.sh`
- Create: `claude/.claude/tests/arm-worktree-guard/cases/20-skips-outside-git.sh`
- Create: `claude/.claude/tests/arm-worktree-guard/cases/30-sweeps-stale-markers.sh`
- Create: `claude/.claude/tests/arm-worktree-guard/cases/40-skips-without-session-id.sh`
- Create: `claude/.claude/tests/arm-worktree-guard/cases/50-skips-bare-repo.sh`
- Modify: `claude/.claude/settings.base.json` -- repoint the `SessionStart` registration

**Interfaces:**
- Consumes: `lib/session.sh` functions `parse_session_id`, `worktree_kind`, `emit_context_with_msg`, and the `STATE_DIR` global.
- Produces: `claude/.claude/hooks/arm-worktree-guard.sh`, registered on `SessionStart`. Task 6 deletes `git-session-start.sh` and relies on this file existing.

- [ ] **Step 1: Write the failing tests**

Create `claude/.claude/tests/arm-worktree-guard/run.sh` -- identical to the Task 1 runner except for these three lines:

```bash
export LIB="$HERE/../../lib/session.sh"
export HOOK="$HERE/../../hooks/arm-worktree-guard.sh"
```

and the header comment `# arm-worktree-guard hook test runner.`

Create `claude/.claude/tests/arm-worktree-guard/helpers.sh`:

```bash
#!/usr/bin/env bash
# Sourced by every case. Sandboxed HOME + git fixtures for the arming hook.
set -uo pipefail

: "${HOOK:?HOOK must be set by run.sh}"

# Physical path — see the note in tests/worktree-guard/helpers.sh and
# tests/session-lib/helpers.sh:12. An unresolved /var/folders path makes
# worktree_kind misread a main checkout as linked, so the hook would skip
# arming and case 00 would fail for the wrong reason.
CASE_TMP="$(cd "$(mktemp -d -t arm-guard-test.XXXXXX)" && pwd -P)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

export HOME="$CASE_TMP/home"
export STATE_DIR="$HOME/.claude/session-worktrees"
mkdir -p "$STATE_DIR"

SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  ( cd "$dir" \
    && git init -q -b feature \
    && git config user.email "test@example.com" \
    && git config user.name "Test" \
    && git config core.hooksPath /dev/null \
    && git commit -q --allow-empty -m "chore(seed): initial" )
}

add_linked_worktree() {
  local dir="$1" name="$2"
  ( cd "$dir" && git worktree add -q -b "wt-$name" ".claude/worktrees/$name" >/dev/null 2>&1 )
  printf '%s' "$dir/.claude/worktrees/$name"
}

# session_start_json [session_id]
session_start_json() {
  jq -cn --arg s "${1:-$SID}" '{session_id:$s, hook_event_name:"SessionStart"}'
}

# run_arm <cwd> <json>  -- runs the hook, discards output, echoes exit status
run_arm() {
  local dir="$1" json="$2"
  ( cd "$dir" && printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1; echo $? )
}

marker_exists() { [[ -f "$STATE_DIR/pending-$SID" ]]; }

assert_marker_present() {
  marker_exists || { echo "  expected marker $STATE_DIR/pending-$SID to exist" >&2; exit 1; }
}

assert_marker_absent() {
  if marker_exists; then
    echo "  expected no marker at $STATE_DIR/pending-$SID" >&2; exit 1
  fi
}
```

`cases/00-arms-in-main-checkout.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"

status=$(run_arm "$repo" "$(session_start_json)")
[[ "$status" == "0" ]] || { echo "  hook exited $status; SessionStart must not block" >&2; exit 1; }
assert_marker_present
```

`cases/10-skips-in-linked-worktree.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"
wt="$(add_linked_worktree "$repo" feat)"

status=$(run_arm "$wt" "$(session_start_json)")
[[ "$status" == "0" ]] || { echo "  hook exited $status; expected 0" >&2; exit 1; }
assert_marker_absent
```

`cases/20-skips-outside-git.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

plain="$CASE_TMP/notarepo"
mkdir -p "$plain"

status=$(run_arm "$plain" "$(session_start_json)")
[[ "$status" == "0" ]] || { echo "  hook exited $status; expected 0" >&2; exit 1; }
assert_marker_absent
```

`cases/40-skips-without-session-id.sh` — note this asserts that **no marker of
any name** exists, not just `pending-$SID`. A regression flipping `-n` to `-z`
on the hook's session-id check would write `pending-` with an empty suffix,
which `assert_marker_absent` would miss entirely:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"

json=$(jq -cn '{session_id:"not-a-uuid", hook_event_name:"SessionStart"}')
status=$(run_arm "$repo" "$json")
[[ "$status" == "0" ]] || { echo "  hook exited $status; expected 0" >&2; exit 1; }

if find "$STATE_DIR" -name 'pending-*' | grep -q .; then
  echo "  hook armed a marker despite having no usable session id" >&2
  exit 1
fi
```

`cases/50-skips-bare-repo.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

bare="$CASE_TMP/bare.git"
mkdir -p "$bare"
(cd "$bare" && git init -q --bare)

status=$(run_arm "$bare" "$(session_start_json)")
[[ "$status" == "0" ]] || { echo "  hook exited $status; expected 0" >&2; exit 1; }
assert_marker_absent
```

`cases/30-sweeps-stale-markers.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/repo"
make_repo "$repo"

# A marker from an abandoned session, older than the 24h cutoff.
stale="$STATE_DIR/pending-99999999-9999-9999-9999-999999999999"
touch "$stale"
touch -t 202001010000 "$stale"

status=$(run_arm "$repo" "$(session_start_json)")
[[ "$status" == "0" ]] || { echo "  hook exited $status; expected 0" >&2; exit 1; }

if [[ -f "$stale" ]]; then
  echo "  stale marker older than 24h was not swept" >&2; exit 1
fi
assert_marker_present
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
cd claude/.claude/tests/arm-worktree-guard && bash run.sh
```

Expected: exit 2 with `missing hook: .../hooks/arm-worktree-guard.sh` -- the runner's precondition check fires before any case runs.

- [ ] **Step 3: Write the hook**

Create `claude/.claude/hooks/arm-worktree-guard.sh`:

```bash
#!/usr/bin/env bash
# arm-worktree-guard.sh — arm the worktree guard for this session.
#
# Event:   SessionStart
# Matcher: n/a
# Exit:    0 always (SessionStart must not block; emits context JSON)
#
# Writes the pending-<session-id> marker that worktree-guard.sh blocks on,
# but only in a main working tree. worktree-entered.sh removes it when
# EnterWorktree runs. This is the only writer of that marker — deleting this
# hook disables worktree isolation silently, so tests/arm-worktree-guard/
# asserts the marker is actually created.
set -euo pipefail

# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

INPUT=$(cat)
SESSION_ID=$(parse_session_id "$INPUT")

# No session id — the marker is keyed by it, so isolation is unavailable.
[[ -n "$SESSION_ID" ]] || exit 0

# Not a git repo, or a bare one: nothing to isolate.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && exit 0

# Already isolated — do not arm.
[[ "$(worktree_kind)" == "linked" ]] && exit 0

# Every fallible call is guarded: a SessionStart hook must exit 0 on every
# path. A trailing bare `exit 0` would NOT be enough -- under `set -e` a
# failing command aborts before the next line runs, so each call guards
# itself. A touch failure therefore fails open (unarmed) rather than
# blocking the session, which is the correct direction here.
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
# Sweep markers from sessions abandoned more than 24 hours ago.
find "$STATE_DIR" -name 'pending-*' -mmin +1440 -delete 2>/dev/null || true

touch "$STATE_DIR/pending-${SESSION_ID}" 2>/dev/null || exit 0

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
emit_context_with_msg "SessionStart" \
  "Main worktree (branch: ${BRANCH}). Call EnterWorktree() before any edits." \
  "[git-workflow] Main worktree (branch: ${BRANCH}). Call EnterWorktree() before any edits." || true

exit 0
```

Make it executable:

```bash
chmod +x claude/.claude/hooks/arm-worktree-guard.sh
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
cd claude/.claude/tests/arm-worktree-guard && bash run.sh
```

Expected: `6 passed, 0 failed`.

If `00-arms-in-main-checkout` fails with the hook exiting non-zero, the likely cause is `set -euo pipefail` combined with `[[ ... ]] && exit 0` as the final command of a conditional -- confirm `worktree_kind` returns a non-empty string.

- [ ] **Step 5: Repoint the SessionStart registration**

In `claude/.claude/settings.base.json`, change the `SessionStart` command:

```
-          "command": "bash $HOME/.claude/hooks/git-session-start.sh"
+          "command": "bash $HOME/.claude/hooks/arm-worktree-guard.sh"
```

Verify:

```bash
jq -r '.hooks.SessionStart[].hooks[].command' claude/.claude/settings.base.json
```

Expected: `bash $HOME/.claude/hooks/arm-worktree-guard.sh`

- [ ] **Step 6: Confirm the guard suite still passes**

```bash
cd claude/.claude/tests/worktree-guard && bash run.sh
```

Expected: `5 passed, 0 failed`.

- [ ] **Step 7: Lint**

```bash
/bin/bash -n claude/.claude/hooks/arm-worktree-guard.sh
shellcheck --severity=warning claude/.claude/hooks/arm-worktree-guard.sh
shfmt -i 2 -ci -bn -l claude/.claude/hooks/arm-worktree-guard.sh claude/.claude/tests/arm-worktree-guard/
```

`/bin/bash -n` must exit 0 -- that is the bash 3.2 parse check, and it is the one that matters. `shfmt -l` must print nothing.

- [ ] **Step 8: Commit**

```bash
git add claude/.claude/hooks/arm-worktree-guard.sh \
        claude/.claude/tests/arm-worktree-guard/run.sh \
        claude/.claude/tests/arm-worktree-guard/helpers.sh \
        claude/.claude/tests/arm-worktree-guard/cases/00-arms-in-main-checkout.sh \
        claude/.claude/tests/arm-worktree-guard/cases/10-skips-in-linked-worktree.sh \
        claude/.claude/tests/arm-worktree-guard/cases/20-skips-outside-git.sh \
        claude/.claude/tests/arm-worktree-guard/cases/30-sweeps-stale-markers.sh \
        claude/.claude/settings.base.json
git commit -m "feat(claude): extract worktree-guard arming into its own hook"
```

`git-session-start.sh` is now unregistered but still on disk. Task 6 deletes it.

---

### Task 3: Remove `no-pr` mode from `git-safety.sh`

`CLAUDE_GIT_WORKFLOW=no-pr` gates two branches. It is live at `no-pr` in the working environment, so both already allow on every invocation. Removing it makes the hook's behaviour independent of an environment variable nothing sets.

**Files:**
- Modify: `claude/.claude/hooks/git-safety.sh:53-56`, `:117`, `:137`
- Create: `claude/.claude/tests/commit-scope/cases/80-merge-on-main-allowed.sh`
- Create: `claude/.claude/tests/commit-scope/cases/81-push-to-main-allowed.sh`
- Create: `claude/.claude/tests/commit-scope/cases/82-commit-on-main-still-blocked.sh`

**Interfaces:**
- Consumes: the `commit-scope` suite's `helpers.sh`, which already provides `init_git_fixture`, `run_hook_in_status`, and `pretooluse_json`.
- Produces: a `git-safety.sh` with no `NO_PR` variable. Task 4 renames the file; Task 5 deletes `workflow_no_pr` from the lib, which is only safe once nothing reads it.

**Note on the fixtures:** `init_git_fixture` creates the repo on branch `feature`, deliberately, so the main-branch guard does not fire. These three cases need `main`, so each renames the branch after init.

- [ ] **Step 1: Write the failing tests**

`claude/.claude/tests/commit-scope/cases/80-merge-on-main-allowed.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# no-pr mode was deleted: merging into main locally is the normal flow here,
# so the hook must not block it regardless of CLAUDE_GIT_WORKFLOW.
dir="$CASE_TMP/mergemain"
mkdir -p "$dir"
init_git_fixture "$dir"
( cd "$dir" && git branch -m main )

unset CLAUDE_GIT_WORKFLOW
status=$(run_hook_in_status "$dir" 'git merge --no-ff topic')
[[ "$status" == "0" ]] \
  || { echo "  hook returned exit=$status; merge on main must be allowed" >&2; exit 1; }
```

`claude/.claude/tests/commit-scope/cases/81-push-to-main-allowed.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Pushing main after a local merge is the normal flow. The permissions.ask
# rules still prompt for it; the hook must not hard-block it.
dir="$CASE_TMP/pushmain"
mkdir -p "$dir"
init_git_fixture "$dir"
( cd "$dir" && git branch -m main )

unset CLAUDE_GIT_WORKFLOW
status=$(run_hook_in_status "$dir" 'git push origin main')
[[ "$status" == "0" ]] \
  || { echo "  hook returned exit=$status; push to main must be allowed" >&2; exit 1; }
```

`claude/.claude/tests/commit-scope/cases/82-commit-on-main-still-blocked.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Commit-on-main was never gated by no-pr mode and must survive its removal.
dir="$CASE_TMP/commitmain"
mkdir -p "$dir"
init_git_fixture "$dir"
( cd "$dir" && git branch -m main )
stage_file "$dir" "src/auth/login.ts" "x"

unset CLAUDE_GIT_WORKFLOW
status=$(run_hook_in_status "$dir" 'git commit -m "feat(auth): add login"')
[[ "$status" == "2" ]] \
  || { echo "  hook returned exit=$status; commit on main must still block" >&2; exit 1; }
```

- [ ] **Step 2: Run the suite to verify 80 and 81 fail**

```bash
cd claude/.claude/tests/commit-scope && bash run.sh
```

Expected: `33 passed, 2 failed`, with `failed cases: 80-merge-on-main-allowed 81-push-to-main-allowed`.

Case 82 passes already -- it is a guard against regressing something the edit must not touch.

- [ ] **Step 3: Delete the `NO_PR` variable**

In `claude/.claude/hooks/git-safety.sh`, remove these four lines (currently 53-56):

```bash
# Per-repo opt-out of PR workflow.
# Canonical gate: workflow_no_pr in lib/session.sh. Inlined here so the hot
# path (~90% of Bash calls) never sources a lib.
NO_PR=false
[[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]] && NO_PR=true
```

- [ ] **Step 4: Delete the three guard blocks**

**Delete the blocks, not just the `NO_PR` conditions.** Removing only
`"$NO_PR" != "true" &&` would leave
`if [[ $COMMAND =~ git merge && $BRANCH == $MAIN_BRANCH ]]`, which *blocks*
every local merge to main -- the opposite of the intent. Merging and pushing
main is the normal flow here.

Delete these three spans, working bottom-up so earlier line numbers stay
valid. Line numbers are from the file as it stands after step 3's four-line
removal has **not** yet been applied -- do step 3 last if you prefer to use
them verbatim, or re-locate by the anchor text shown.

| Lines | Anchor text on the first line | What goes |
| --- | --- | --- |
| 135-201 | `# --- Block push to main (checks destination ref, not just current branch) ---` | the whole `if` block through its closing `fi` at 201, including the `BLOCKED: Cannot push directly to` message and all `block_push` refspec logic |
| 126-133 | `# --- Allow remote branch deletion (not a push to any branch) ---` | the whole block through `fi` at 133. Its only purpose is letting `git push --delete` escape the push guard above; with that guard gone it exits 0 for a command that already would |
| 115-124 | `# --- Block merge/rebase/cherry-pick on main (enforce PR workflow) ---` | the whole `if` block through its closing `fi` at 124, including the `BLOCKED: Cannot merge/rebase/cherry-pick` message |

Pushing main is still gated by `Bash(git push origin main*)`,
`Bash(git push * main*)`, and `Bash(git push * master*)` in
`permissions.ask`, which this change does not touch.

- [ ] **Step 5: Confirm no `NO_PR` reference survives**

```bash
grep -n 'NO_PR\|CLAUDE_GIT_WORKFLOW\|block_push' claude/.claude/hooks/git-safety.sh
```

Expected: no output.

- [ ] **Step 6: Run the suite to verify it passes**

```bash
cd claude/.claude/tests/commit-scope && bash run.sh
```

Expected: `35 passed, 0 failed`.

- [ ] **Step 7: Lint**

```bash
/bin/bash -n claude/.claude/hooks/git-safety.sh
shellcheck --severity=warning claude/.claude/hooks/git-safety.sh
shfmt -i 2 -ci -bn -l claude/.claude/hooks/git-safety.sh
```

- [ ] **Step 8: Commit**

```bash
git add claude/.claude/hooks/git-safety.sh \
        claude/.claude/tests/commit-scope/cases/80-merge-on-main-allowed.sh \
        claude/.claude/tests/commit-scope/cases/81-push-to-main-allowed.sh \
        claude/.claude/tests/commit-scope/cases/82-commit-on-main-still-blocked.sh
git commit -m "refactor(claude): drop no-pr mode from the git hook"
```

---

### Task 4: Rename `git-safety.sh` to `commit-guard.sh`

Mechanical rename. Split from Task 3 so a reviewer can accept the behaviour change and the rename independently.

**Files:**
- Rename: `claude/.claude/hooks/git-safety.sh` -> `claude/.claude/hooks/commit-guard.sh`
- Modify: `claude/.claude/tests/commit-scope/run.sh` -- the `HOOK` export
- Modify: `claude/.claude/settings.base.json` -- the `PreToolUse`/`Bash` command

**Interfaces:**
- Consumes: the file produced by Task 3.
- Produces: `hooks/commit-guard.sh`. Task 6's settings rewrite and Task 8's documentation both name it.

- [ ] **Step 1: Rename with git so history follows**

```bash
git mv claude/.claude/hooks/git-safety.sh claude/.claude/hooks/commit-guard.sh
```

- [ ] **Step 2: Update the header comment**

In `claude/.claude/hooks/commit-guard.sh`, line 2:

```bash
-# git-safety.sh — guard git Bash calls: main-branch + commit scope/atomicity.
+# commit-guard.sh — guard git Bash calls: commit atomicity, scope, no commit on main.
```

- [ ] **Step 3: Update the test runner**

In `claude/.claude/tests/commit-scope/run.sh`:

```bash
-export HOOK="$HERE/../../hooks/git-safety.sh"
+export HOOK="$HERE/../../hooks/commit-guard.sh"
```

- [ ] **Step 4: Update the registration**

In `claude/.claude/settings.base.json`, the `PreToolUse` entry with matcher `Bash`:

```
-          "command": "bash $HOME/.claude/hooks/git-safety.sh"
+          "command": "bash $HOME/.claude/hooks/commit-guard.sh"
```

- [ ] **Step 5: Verify no `git-safety` reference remains in live code**

```bash
grep -rn 'git-safety' claude/ bin/ tmux/ CLAUDE.md --include='*.sh' --include='*.json' --include='*.conf' --include='*.md'
```

Expected: no output. Hits under `docs/superpowers/` are frozen plan and spec documents -- leave them.

- [ ] **Step 6: Run the suite**

```bash
cd claude/.claude/tests/commit-scope && bash run.sh
```

Expected: `35 passed, 0 failed`. A failure here almost certainly means step 3 was missed -- the runner exits 2 with `missing hook:` when the path is wrong.

- [ ] **Step 7: Commit**

```bash
git add claude/.claude/hooks/commit-guard.sh \
        claude/.claude/tests/commit-scope/run.sh \
        claude/.claude/settings.base.json
git commit -m "refactor(claude): rename git-safety hook to commit-guard"
```

---

### Task 5: Delete the no-pr caller hooks, trim the libs, and fix the symlink defect

`workflow_no_pr` and `run_timeout` are both about to lose their callers, but
not the ones an earlier draft of this plan assumed. The full caller set,
measured rather than guessed:

| Function | Callers | Registered? |
| --- | --- | --- |
| `workflow_no_pr` | `restore-git-context.sh:47,52` | yes -- `PostCompact` |
| | `worktree-exited.sh:15` | yes -- `PostToolUse`/`ExitWorktree` |
| | `git-session-start.sh:160` | no -- unregistered by Task 2 |
| `run_timeout` | `resolve-pr-refs.sh:75,96` | yes -- `UserPromptSubmit`, fires on every message |
| | `git-session-start.sh:118` | no |

Deleting either function while any of those hooks is still on disk and
registered leaves it sourcing a lib symbol that no longer exists, which under
`set -euo pipefail` aborts the hook on every `PostCompact` and every user
prompt. So this task deletes the callers first, in their own commit.

**Three commits, in this order.** The callers must die before the functions they call, or the tree is broken between commits.

1. Delete the four hooks that call `workflow_no_pr` or `run_timeout`, plus their registrations.
2. Delete the two now-orphaned lib functions and their test cases.
3. Fix the symlink defect found while writing the Task 1 suite: `worktree_kind` and `check_worktree_pending` compare a symlink-resolved path against an unresolved one, so a main checkout reached through a symlink is misreported as a linked worktree and worktree isolation silently switches off.

**Files:**
- Delete: `claude/.claude/hooks/restore-git-context.sh` (calls `workflow_no_pr`; registered on `PostCompact`)
- Delete: `claude/.claude/hooks/resolve-pr-refs.sh` (calls `run_timeout`; registered on `UserPromptSubmit`)
- Delete: `claude/.claude/hooks/worktree-exited.sh` (calls `workflow_no_pr`; registered on `PostToolUse`/`ExitWorktree`)
- Delete: `claude/.claude/hooks/git-session-start.sh` (calls both; already unregistered by Task 2)
- Modify: `claude/.claude/settings.base.json` -- remove the `UserPromptSubmit`, `PostCompact`, and `PostToolUse`/`ExitWorktree` registrations
- Modify: `claude/.claude/lib/session.sh` -- delete `workflow_no_pr`; `pwd -P` in two comparisons
- Modify: `claude/.claude/lib/portability.sh` -- delete `run_timeout`
- Delete: `claude/.claude/tests/session-lib/cases/30-workflow-no-pr-set.sh`
- Delete: `claude/.claude/tests/session-lib/cases/31-workflow-no-pr-unset.sh`
- Create: `claude/.claude/tests/session-lib/cases/23-worktree-kind-main-via-symlink.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces: `lib/session.sh` exporting `emit_context`, `emit_context_with_msg`, `parse_session_id`, `pending_file`, `check_worktree_pending`, `cwd_repo_hint`, `worktree_kind`, and the `STATE_DIR` global. `lib/portability.sh` exporting `file_mtime` and `to_lower`.

- [ ] **Step 1: Confirm the caller set before deleting anything**

```bash
grep -rn 'workflow_no_pr' claude/ bin/ --include='*.sh' --include='*.json'
grep -rn 'run_timeout' claude/ bin/ --include='*.sh' --include='*.json'
```

Expected, and nothing else: the two definitions in `lib/session.sh` and
`lib/portability.sh`, the four hooks in the table above, and the two
`session-lib` test cases. If a caller appears that is not in that table,
**stop and report it** — the whole point of this step is that an earlier
draft of this plan got the caller set wrong.

- [ ] **Step 2: Delete the four caller hooks**

```bash
git rm claude/.claude/hooks/restore-git-context.sh \
       claude/.claude/hooks/resolve-pr-refs.sh \
       claude/.claude/hooks/worktree-exited.sh \
       claude/.claude/hooks/git-session-start.sh
```

- [ ] **Step 3: Remove their three registrations**

In `claude/.claude/settings.base.json`, delete:

- the entire `"UserPromptSubmit"` key and its array (`resolve-pr-refs.sh` was its only entry)
- the entire `"PostCompact"` key and its array (`restore-git-context.sh` was its only entry)
- the `PostToolUse` entry whose matcher is `ExitWorktree` (`worktree-exited.sh`), leaving the other `PostToolUse` entries in place

`git-session-start.sh` needs no registration change — Task 2 already
repointed `SessionStart` to `arm-worktree-guard.sh`.

Validate before moving on:

```bash
jq empty claude/.claude/settings.base.json && echo "valid JSON"
jq -r '.hooks | keys[]' claude/.claude/settings.base.json
```

The key list must no longer contain `UserPromptSubmit` or `PostCompact`.

- [ ] **Step 3b: Commit the caller deletions on their own**

This is commit 1 of three. The tree must work at this point: the functions
still exist, and nothing calls them any more.

```bash
git add claude/.claude/settings.base.json
git commit -m "refactor(claude): delete the hooks that depend on no-pr mode and run_timeout"
```

`git rm` already staged the four file deletions.

- [ ] **Step 3c: Delete the two obsolete test cases**

```bash
git rm claude/.claude/tests/session-lib/cases/30-workflow-no-pr-set.sh \
       claude/.claude/tests/session-lib/cases/31-workflow-no-pr-unset.sh
```

- [ ] **Step 4: Delete `workflow_no_pr` from the lib**

In `claude/.claude/lib/session.sh`, remove the function and its documentation
block (around lines 133-143), ending with the closing `}` of:

```bash
workflow_no_pr() {
  [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]
}
```

- [ ] **Step 5: Delete `run_timeout` from portability**

In `claude/.claude/lib/portability.sh`, remove the `run_timeout` function and its documentation block. Keep `file_mtime` and `to_lower`.

`to_lower` has no caller after this change and stays deliberately: `CLAUDE.md` names it as the bash-3.2 lowercase escape hatch, and the next hook that needs one must find it rather than reinvent `${x,,}`.

- [ ] **Step 6: Confirm the removals are complete**

```bash
grep -rn 'workflow_no_pr\|run_timeout' claude/ bin/ --include='*.sh' --include='*.json'
```

Expected: no output.

- [ ] **Step 7: Run every suite that sources these libs**

```bash
cd claude/.claude/tests/session-lib && bash run.sh
```

Expected: `5 passed, 0 failed` (7 cases minus the 2 deleted).

```bash
cd claude/.claude/tests/commit-scope && bash run.sh
```

Expected: `35 passed, 0 failed`.

```bash
cd claude/.claude/tests/worktree-guard && bash run.sh
```

Expected: `5 passed, 0 failed`.

```bash
cd claude/.claude/tests/arm-worktree-guard && bash run.sh
```

Expected: `6 passed, 0 failed`.

- [ ] **Step 8: Lint**

```bash
/bin/bash -n claude/.claude/lib/session.sh
/bin/bash -n claude/.claude/lib/portability.sh
shellcheck --severity=warning claude/.claude/lib/session.sh claude/.claude/lib/portability.sh
```

- [ ] **Step 9: Commit the lib trim**

This is commit 2 of three. `settings.base.json` is **not** in this commit —
its registration removals belong to commit 1.

```bash
git add claude/.claude/lib/session.sh \
        claude/.claude/lib/portability.sh
git commit -m "refactor(claude): drop the now-orphaned workflow_no_pr and run_timeout"
```

`git rm` already staged the two test-case deletions, so they ride along here.

**This task produces a third commit.** Steps 10-14 fix a defect found while
writing the Task 1 suite. It is a behaviour change, not a trim, so it is
committed separately.

- [ ] **Step 10: Write the failing regression test**

`worktree_kind` compares `git rev-parse --absolute-git-dir`, which resolves
symlinks, against `cd "$(git rev-parse --git-common-dir)" && pwd`, which does
not. In a **main** checkout reached through a symlinked path the two differ,
so the function returns `linked`. `check_worktree_pending` then treats the
pending marker as stale, deletes it, and allows the edit -- worktree
isolation silently off.

Measured on this machine: `absolute-git-dir` gave
`/private/var/folders/.../repo/.git` while `common + pwd` gave
`/var/folders/.../repo/.git`.

Create `claude/.claude/tests/session-lib/cases/23-worktree-kind-main-via-symlink.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# A MAIN checkout whose path is reached through a symlink must still report
# "main". git rev-parse --absolute-git-dir resolves symlinks; `cd ... && pwd`
# does not, so an asymmetric comparison reports "linked" here and silently
# disables worktree isolation.
#
# This case deliberately does NOT canonicalise: the unresolved path IS the
# input under test. helpers.sh canonicalises CASE_TMP, so build the
# unresolved path explicitly.
raw="$(mktemp -d -t wk-symlink.XXXXXX)"
trap 'rm -rf "$raw"' EXIT
mkdir -p "$raw/repo"
( cd "$raw/repo" \
  && git init -q -b main \
  && git config user.email "test@example.com" \
  && git config user.name "Test" \
  && git config core.hooksPath /dev/null \
  && git commit -q --allow-empty -m "chore(seed): initial" )

got=$( cd "$raw/repo" && source "$LIB" && worktree_kind )
[[ "$got" == "main" ]] \
  || { echo "  worktree_kind returned '$got' for a main checkout reached via a symlink; want 'main'" >&2; exit 1; }
```

- [ ] **Step 11: Run it to verify it fails**

```bash
cd claude/.claude/tests/session-lib && bash run.sh
```

Expected: `5 passed, 1 failed`, with `failed cases: 23-worktree-kind-main-via-symlink`
and the message `worktree_kind returned 'linked' ... want 'main'`.

If it passes already, `mktemp` on this machine is not returning a symlinked
path. Report that rather than proceeding -- the fix would then be unverified.

- [ ] **Step 12: Make both comparisons symmetric**

In `claude/.claude/lib/session.sh`, in `worktree_kind`:

```bash
-  common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
+  common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P || true)
```

And in `check_worktree_pending`, which repeats the same comparison:

```bash
-  git_com=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
+  git_com=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P || true)
```

`pwd -P` is POSIX and present in bash 3.2. Do not switch to `realpath` --
it is not on stock macOS.

- [ ] **Step 13: Run every affected suite**

```bash
cd claude/.claude/tests/session-lib && bash run.sh
```

Expected: `6 passed, 0 failed`.

```bash
cd claude/.claude/tests/worktree-guard && bash run.sh
```

Expected: `5 passed, 0 failed`. This suite canonicalises its own fixture
path, so it passed before the fix and must still pass after it.

```bash
cd claude/.claude/tests/arm-worktree-guard && bash run.sh
```

Expected: `6 passed, 0 failed`.

```bash
cd claude/.claude/tests/commit-scope && bash run.sh
```

Expected: `35 passed, 0 failed`.

- [ ] **Step 14: Commit the fix separately**

```bash
git add claude/.claude/lib/session.sh \
        claude/.claude/tests/session-lib/cases/23-worktree-kind-main-via-symlink.sh
git commit -m "fix(claude): compare physical paths when detecting a linked worktree"
```

---

### Task 6: Delete the remaining hooks and reduce the registrations to four

The bulk deletion. Everything removed here is unreachable from the three enforcements.

**Files:**
- Delete: `claude/.claude/hooks/read-once.sh`, `read-once-gc.sh`, `notify.sh`, `failure-recovery.sh`, `audit-log.sh`, `permission-policy.sh`
- Delete: `claude/.claude/lib/read-once-cache.sh`, `permission-policy.sh`, `notify-pane.sh`
- Delete: `claude/.claude/tests/read-once/`, `claude/.claude/tests/permission-policy/`, `claude/.claude/tests/notify-pane/`
- Modify: `claude/.claude/settings.base.json` -- the `hooks` object

**Interfaces:**
- Consumes: `arm-worktree-guard.sh` from Task 2 (this task deletes its predecessor) and `commit-guard.sh` from Task 4.
- Produces: a `hooks` object with exactly four registrations, asserted in step 4.

- [ ] **Step 1: Delete the hooks and libs**

```bash
git rm claude/.claude/hooks/read-once.sh \
       claude/.claude/hooks/read-once-gc.sh \
       claude/.claude/hooks/notify.sh \
       claude/.claude/hooks/failure-recovery.sh \
       claude/.claude/hooks/audit-log.sh \
       claude/.claude/hooks/permission-policy.sh
```

`git-session-start.sh`, `resolve-pr-refs.sh`, `restore-git-context.sh`, and
`worktree-exited.sh` are **not** here — Task 5 deleted them, because they call
`workflow_no_pr` or `run_timeout` and had to go before those functions did.

```bash
git rm claude/.claude/lib/read-once-cache.sh \
       claude/.claude/lib/permission-policy.sh \
       claude/.claude/lib/notify-pane.sh
```

- [ ] **Step 2: Delete the three obsolete test suites**

```bash
git rm -r claude/.claude/tests/read-once claude/.claude/tests/permission-policy claude/.claude/tests/notify-pane
```

- [ ] **Step 3: Replace the `hooks` object**

In `claude/.claude/settings.base.json`, replace the entire `"hooks": { ... }` value (currently lines 191-337) with:

```json
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/hooks/arm-worktree-guard.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/hooks/commit-guard.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/hooks/worktree-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "EnterWorktree",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/hooks/worktree-entered.sh"
          }
        ]
      }
    ]
  },
```

Keep the trailing comma -- `hooks` is not the last key in the object.

- [ ] **Step 4: Assert the registration set**

```bash
jq empty claude/.claude/settings.base.json && echo "valid JSON"
jq -r '.hooks | to_entries[] | .key as $e | .value[] | (.matcher // "-") as $m | .hooks[] | "\($e)\t\($m)\t\(.command)"' claude/.claude/settings.base.json
```

Expected exactly four lines:

```
SessionStart	-	bash $HOME/.claude/hooks/arm-worktree-guard.sh
PreToolUse	Bash	bash $HOME/.claude/hooks/commit-guard.sh
PreToolUse	Write|Edit|NotebookEdit	bash $HOME/.claude/hooks/worktree-guard.sh
PostToolUse	EnterWorktree	bash $HOME/.claude/hooks/worktree-entered.sh
```

- [ ] **Step 5: Assert every registered hook exists on disk**

A registration pointing at a deleted file is the silent-failure mode this whole change is meant to remove.

```bash
jq -r '.hooks[][].hooks[].command' claude/.claude/settings.base.json \
  | sed 's|bash \$HOME/.claude/|claude/.claude/|' \
  | xargs ls -l
```

Expected: four files listed, none missing.

- [ ] **Step 6: Assert `permissions` was not touched**

```bash
jq -r '.permissions.deny | length' claude/.claude/settings.base.json
jq -r '.permissions.ask  | length' claude/.claude/settings.base.json
```

Expected: `52` and `84`.

- [ ] **Step 7: Run the four surviving hook suites**

```bash
cd claude/.claude/tests/commit-scope && bash run.sh
```

Expected: `35 passed, 0 failed`.

```bash
cd claude/.claude/tests/worktree-guard && bash run.sh
```

Expected: `5 passed, 0 failed`.

```bash
cd claude/.claude/tests/arm-worktree-guard && bash run.sh
```

Expected: `6 passed, 0 failed`.

```bash
cd claude/.claude/tests/session-lib && bash run.sh
```

Expected: `5 passed, 0 failed`.

- [ ] **Step 8: Run the remaining suites**

```bash
cd claude/.claude/tests/bash-portability && bash run.sh
```

Expected: all passed.

```bash
cd claude/.claude/tests/mcp-permission-overlay && bash run.sh
```

Expected: all passed.

```bash
cd claude/.claude/tests/output-style && bash run.sh
```

Expected: all passed.

```bash
cd claude/.claude/tests/theme-contrast && bash run.sh
```

Expected: all passed.

- [ ] **Step 9: Commit**

```bash
git add claude/.claude/settings.base.json
git commit -m "refactor(claude): delete the non-enforcement hook layer"
```

The `git rm` calls in steps 1-2 already staged 12 file deletions and three directory deletions.

---

### Task 7: Retire the `tmux-attention` component

Its only producer was `notify.sh`, deleted in Task 6. `tmux-attention` also reads `~/.cache/codex/attention`, but that directory does not exist and no codex hook writes it, so the component now has no input at all -- the badge renders empty forever and the picker always reports "No panes need attention." herdr replaced it as the agent workspace manager.

**Files:**
- Delete: `bin/.local/bin/tmux-attention`, `tmux-attention-badge`, `tmux-attention-picker`
- Modify: `tmux/.config/tmux/tmux.conf:53`, `:54`, `:78`, `:85`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. This task is purely subtractive.

- [ ] **Step 1: Delete the three scripts**

```bash
git rm bin/.local/bin/tmux-attention \
       bin/.local/bin/tmux-attention-badge \
       bin/.local/bin/tmux-attention-picker
```

- [ ] **Step 2: Remove the two key bindings**

In `tmux/.config/tmux/tmux.conf`, delete lines 53 and 54:

```
bind-key a run-shell "tmux-attention"
bind-key A display-popup -E -w 80% -h 80% "tmux-attention-picker"
```

- [ ] **Step 3: Replace the status-right base assignment**

Line 78 is the **base** `set -g`; lines 79-80 are `set -ag` appends for the
catppuccin session and host segments. Deleting line 78 would make the first
append land on tmux's built-in default `status-right` (pane title and clock),
which shows up as a visible regression rather than a removal. Replace it:

```
-set -g status-right "#[fg=#f38ba8]#(tmux-attention-badge)#[default] "
+set -g status-right ""
```

- [ ] **Step 4: Remove the focus hook**

Delete line 85 and its comment on line 84:

```
# Auto-dismiss Claude Code attention markers when a pane gains focus.
set-hook -g pane-focus-in "run-shell -b 'tmux-attention --clear-focused'"
```

- [ ] **Step 5: Verify no reference survives**

```bash
grep -rn 'tmux-attention\|claude/attention\|codex/attention' bin/ tmux/ claude/ CLAUDE.md
```

Expected: no output.

- [ ] **Step 6: Verify the tmux config still parses**

```bash
tmux -f tmux/.config/tmux/tmux.conf -L planchk start-server \; kill-server && echo "tmux config OK"
```

Expected: `tmux config OK`. This starts a throwaway server on socket `planchk` and immediately kills it, so your running tmux session is untouched. If tmux reports a syntax error it prints the offending line number.

- [ ] **Step 7: Run the stow hygiene suite**

`bin/` changed, and that suite checks every package with a `tests/` directory carries a `.stow-local-ignore`.

```bash
cd bin/tests/stow-hygiene && bash run.sh
```

Expected: all passed.

- [ ] **Step 8: Commit**

```bash
git add tmux/.config/tmux/tmux.conf
git commit -m "refactor(tmux-attention): retire the attention switcher for herdr"
```

The `git rm` in step 1 already staged the three script deletions.

---

### Task 8: Update the documentation

Six documents describe a hook layer that no longer exists. Leaving them is the dangling-pointer bug the previous branch shipped and had to correct.

**Files:**
- Modify: `claude/.claude/hooks/README.md` -- rewrite
- Modify: `CLAUDE.md` -- four sections

**Interfaces:**
- Consumes: the final state from Tasks 1-7.
- Produces: documentation matching it.

- [ ] **Step 1: Rewrite the hooks README**

Replace `claude/.claude/hooks/README.md` entirely:

````markdown
# Claude Code Hooks

Four shell hooks enforcing three things: worktree isolation, atomic commits,
and conventional commit scope. Nothing else. They are registered in
`claude/.claude/settings.base.json` under `hooks` (merged with
`settings.overlay.json` by `claude-sync` into `~/.claude/settings.json`). The
`claude` package stows to `~/.claude/`, so each hook runs as
`bash $HOME/.claude/hooks/<name>.sh`.

## Conventions

- **Shebang:** `#!/usr/bin/env bash`. A deliberate deviation from Google Shell
  Style Guide §2 (`#!/bin/bash`): macOS ships bash 3.2 at `/bin/bash` while
  Homebrew bash 5 lives elsewhere. Registrations name the interpreter, so the
  shebang is never consulted at runtime -- **every hook must be bash 3.2
  syntax regardless**.
- **Exit codes:** PreToolUse `exit 0` = allow, `exit 2` = block (stderr shown
  to Claude). SessionStart and PostToolUse emit structured JSON and must not
  block.
- **Style:** Google Shell Style Guide, `shfmt -i 2 -ci -bn`,
  `shellcheck --severity=warning`.

## The hooks

| Hook | Event | Matcher | Purpose | Exit |
| --- | --- | --- | --- | --- |
| `arm-worktree-guard.sh` | SessionStart | n/a | write `pending-<session-id>`; sweep markers older than 24h | 0 |
| `commit-guard.sh` | PreToolUse | `Bash` | block `git add -A/--all/--update/.` and `git commit -a`; block commit on main; warn on bad commit scope | 0 / 2 |
| `worktree-guard.sh` | PreToolUse | `Write\|Edit\|NotebookEdit` | block edits inside the repo until `EnterWorktree()` | 0 / 2 |
| `worktree-entered.sh` | PostToolUse | `EnterWorktree` | remove the marker | 0 |

## Worktree isolation is three files

`arm-worktree-guard.sh` writes `~/.claude/session-worktrees/pending-<id>`,
`worktree-guard.sh` blocks while it exists, `worktree-entered.sh` removes it.
**The arming hook is the only writer of that marker.** Deleting it leaves the
guard registered, its tests passing, and nothing enforced --
`tests/arm-worktree-guard/cases/00-arms-in-main-checkout.sh` exists to catch
exactly that.

Escape hatch: `rm ~/.claude/session-worktrees/pending-<id>`, printed in the
block message.

## Shared libraries (`../lib/`)

| Lib | Role | Key functions |
| --- | --- | --- |
| `session.sh` | session id, marker path, worktree detection, context emit | `emit_context`, `emit_context_with_msg`, `parse_session_id`, `pending_file`, `check_worktree_pending`, `cwd_repo_hint`, `worktree_kind` |
| `commit-scope.sh` | commit-scope signals S1-S4 | `is_banned_scope`, `suggest_scope` |
| `portability.sh` | bash 3.2 / cross-platform helpers | `file_mtime`, `to_lower` |

`to_lower` currently has no caller. It stays as the documented landing spot
for the next hook that needs lowercasing, because `${x,,}` fails silently
under bash 3.2.

## Tests (`../tests/`)

Each suite iterates `cases/*.sh` and exits non-zero on any failure:

```sh
cd claude/.claude/tests/<suite> && bash run.sh
```

| Suite | Covers |
| --- | --- |
| `commit-scope/` | `lib/commit-scope.sh` + `commit-guard.sh` |
| `worktree-guard/` | `worktree-guard.sh` block and allow branches |
| `arm-worktree-guard/` | `arm-worktree-guard.sh` marker writing and sweeping |
| `session-lib/` | `lib/session.sh` (and `portability.sh`, which it sources) |

`settings.base.json` is the source of truth for matchers; the table above is
documentation.
````

- [ ] **Step 2: Update the bash 3.2 section in `CLAUDE.md`**

The section is headed `### Hook shell constraint (bash 3.2)`. Its count is
now wrong -- there are 4 Claude registrations plus 2 codex ones. Change:

```
-Hook registrations name the interpreter -- `bash $HOME/.claude/hooks/<x>.sh`,
-16 of them across `settings.base.json` and `codex/.codex/config.base.toml` --
+Hook registrations name the interpreter -- `bash $HOME/.claude/hooks/<x>.sh`,
+6 of them across `settings.base.json` and `codex/.codex/config.base.toml` --
```

In the same section, the sentence naming three dead hooks refers to files that
no longer exist. Replace:

```
-Three hooks were entirely dead this way --
-`check_web_fetch`, `read-once`, and `notify-pane` pane resolution.
+Three hooks were entirely dead this way before being found; all three have
+since been deleted for unrelated reasons, but the failure mode has not
+changed.
```

- [ ] **Step 3: Delete the semantic policy hook section from `CLAUDE.md`**

Remove the entire `### Semantic policy hook` section, from its heading through
the code block listing the lib and test paths, ending just before
`# Commit scope`. The hook it documents no longer exists.

In the `## Permission posture` section immediately above, the `deny`/`ask`
rules described there are unaffected and stay.

- [ ] **Step 4: Update the `# Commit scope` section in `CLAUDE.md`**

```
-Read the file contents before choosing scope. The
-`claude/.claude/hooks/git-safety.sh` hook emits a non-blocking warning
+Read the file contents before choosing scope. The
+`claude/.claude/hooks/commit-guard.sh` hook emits a non-blocking warning
```

- [ ] **Step 5: Update the staging rule in `CLAUDE.md`**

Find the line ending `Hook-enforced.` in the secrets/staging guidance and make
the enforcer explicit:

```
-Hook-enforced.
+Enforced by `claude/.claude/hooks/commit-guard.sh`.
```

- [ ] **Step 5b: Fix the two stale `git-safety` references in surviving files**

Task 4 renamed the hook but deliberately left comment references alone. Most
of them die with their files in Tasks 6-7, but these two live in files that
survive the whole change and are named by no other task:

`claude/.claude/lib/commit-scope.sh:3`:

```
-#                   Sourced by hooks/git-safety.sh and tests/commit-scope.
+#                   Sourced by hooks/commit-guard.sh and tests/commit-scope.
```

`claude/.claude/tests/commit-scope/helpers.sh:40`:

```
-# Uses a feature branch (not main) so git-safety.sh's main-branch guard does
+# Uses a feature branch (not main) so commit-guard.sh's main-branch guard does
```

Re-run the suite afterwards — both are comments, so it must stay at
`35 passed, 0 failed`:

```bash
cd claude/.claude/tests/commit-scope && bash run.sh
```

- [ ] **Step 6: Update the package-conventions bullet in `CLAUDE.md`**

The bullet beginning "The `claude/` package stows to `~/.claude/`" describes
"hooks, rules, plugins, and project instructions". That is still accurate --
leave it. But verify no other sentence in that section names a deleted file:

```bash
grep -n 'read-once\|permission-policy\|audit-log\|notify\|resolve-pr-refs\|failure-recovery\|restore-git-context\|git-session-start\|git-safety\|tmux-attention' CLAUDE.md
```

Expected: no output. Fix any hit before continuing.

- [ ] **Step 7: Full dangling-reference sweep**

```bash
grep -rn 'git-safety\|permission-policy\|read-once\|notify-pane\|notify\.sh\|git-session-start\|resolve-pr-refs\|failure-recovery\|restore-git-context\|audit-log\|worktree-exited\|workflow_no_pr\|tmux-attention\|claude/attention' \
  --include='*.sh' --include='*.json' --include='*.conf' --include='*.md' \
  claude/ bin/ tmux/ CLAUDE.md
```

Expected: no output. Hits under `docs/` are frozen plan and spec documents and
are left alone -- this sweep deliberately does not search there.

- [ ] **Step 8: Run every suite one final time**

```bash
cd claude/.claude/tests/commit-scope && bash run.sh
```

```bash
cd claude/.claude/tests/worktree-guard && bash run.sh
```

```bash
cd claude/.claude/tests/arm-worktree-guard && bash run.sh
```

```bash
cd claude/.claude/tests/session-lib && bash run.sh
```

```bash
cd claude/.claude/tests/bash-portability && bash run.sh
```

```bash
cd claude/.claude/tests/mcp-permission-overlay && bash run.sh
```

```bash
cd claude/.claude/tests/output-style && bash run.sh
```

```bash
cd claude/.claude/tests/theme-contrast && bash run.sh
```

```bash
cd bin/tests/stow-hygiene && bash run.sh
```

All must pass.

- [ ] **Step 9: Commit**

```bash
git add claude/.claude/hooks/README.md CLAUDE.md
git commit -m "docs(claude): rewrite hook docs for the four-hook layer"
```

---

## After Merge

These steps run from the **main checkout**, never from a worktree. Stow
resolves links relative to the package directory it is given, so stowing from
`.claude/worktrees/<name>/` produces symlinks into a directory that disappears
when the worktree is removed.

- [ ] **Restow the three affected packages**

```bash
cd ~/workspace/dotfiles && stow -t ~ -R claude
cd ~/workspace/dotfiles && stow -t ~ -R bin
cd ~/workspace/dotfiles && stow -t ~ -R tmux
```

- [ ] **Confirm no dangling symlinks**

```bash
find ~/.claude/hooks ~/.claude/lib ~/.local/bin -type l ! -exec test -e {} \; -print
```

Expected: no output. Deleted and renamed stowed files leave dead links exactly
as `CLAUDE.company.md` did; `stow -R` is what clears them.

- [ ] **Regenerate the live settings**

```bash
claude-sync
jq -r '.hooks | to_entries[] | .key as $e | .value[] | (.matcher // "-") as $m | .hooks[] | "\($e)\t\($m)\t\(.command)"' ~/.claude/settings.json
```

Expected: the same four lines asserted in Task 6 step 4.

- [ ] **Reload tmux**

```bash
tmux source-file ~/.config/tmux/tmux.conf
```

The status bar should lose the attention badge and keep the catppuccin session
and host segments.

- [ ] **Verify enforcement end to end in a fresh session**

Start a new Claude Code session in the main checkout and attempt a file edit.
It must be blocked with `BLOCKED: This session requires an isolated git
worktree before file edits.` If the edit is allowed, `arm-worktree-guard.sh`
did not run -- check `ls ~/.claude/session-worktrees/` and
`jq '.hooks.SessionStart' ~/.claude/settings.json`.

This is the one check no test can perform, because it exercises the real
SessionStart event rather than a synthesized payload.
