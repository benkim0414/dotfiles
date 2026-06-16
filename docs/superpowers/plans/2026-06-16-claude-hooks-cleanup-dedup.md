# Claude Hooks Cleanup + Dedup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove dead `MultiEdit` references from the Claude Code hooks and dedup three copy-pasted logic blocks into `lib/session.sh` helpers, with behavior preserved exactly.

**Architecture:** Two mechanical cleanup commits first (comment fixes, dead-branch removal), then three TDD helper commits (`cwd_repo_hint`, `worktree_kind`, `workflow_no_pr`) each adding the helper to `lib/session.sh`, a test case under a new `tests/session-lib/` harness, and adopting the helper in the hooks that duplicated it.

**Tech Stack:** Bash 3.2+ (macOS/Linux portable), `jq`, the existing `claude/.claude/tests/` shell-test convention (`run.sh` iterates `cases/*.sh`, each sources `helpers.sh`).

---

## Scope & coverage notes

- Spec: `docs/superpowers/specs/2026-06-16-claude-hooks-cleanup-dedup-design.md`.
- **Commit scope is `claude` on every commit** (the Stow package these files live in; `git log` shows `(claude)` is the dominant scope on hook/lib files — 138 vs `hooks` 22). `hooks`/`session`/`read-once` are subdir/artifact names, not components.
- This plan refines the spec's "expected" 6-commit split to **5 commits**: the test cases ride with the helper commit that introduces them (TDD: test + code + adoption are one self-contained change) rather than a separate trailing test commit. Same scope discipline.
- `git-safety.sh` is touched in three commits (comments in Task 1; lazy-source adoption in Task 3; pointer comment in Task 5) — each a distinct logical change on different lines.

## Regression guard (do NOT undo)

While editing, preserve these merged historical fixes:
- PostCompact routes through `emit_context`, which emits `systemMessage` (not `additionalContext`) — `restore-git-context.sh` must keep calling `emit_context`.
- `restore-git-context.sh` bare-repo guard (line ~34) stays; `worktree_kind` independently returns `none` for bare repos but the early guard must remain.
- No change to `read-once.*` or any numeric mtime / `@tsv` parsing.

## Baseline (run once before starting)

- [ ] **Confirm suites green before any edit**

Run:
```bash
bash claude/.claude/tests/permission-policy/run.sh | tail -1
bash claude/.claude/tests/commit-scope/run.sh | tail -1
```
Expected: `13 passed, 0 failed` and `32 passed, 0 failed`.

---

## Task 1: Correct file-editing matcher comments (C4 + C3 comments)

Removes `MultiEdit` from descriptive comments and fixes the matcher text to the real registration (`Write|Edit|NotebookEdit`). Comment-only — no runtime effect.

**Files:**
- Modify: `claude/.claude/hooks/git-safety.sh:5`, `:53`
- Modify: `claude/.claude/hooks/worktree-guard.sh:2`

- [ ] **Step 1: Fix git-safety.sh header comment (line 5)**

Edit `claude/.claude/hooks/git-safety.sh`, replace:
```bash
# (matcher: Write|Edit|MultiEdit|NotebookEdit).
```
with:
```bash
# (matcher: Write|Edit|NotebookEdit).
```

- [ ] **Step 2: Fix git-safety.sh NOTE comment (line 53)**

Replace:
```bash
# NOTE: Worktree isolation for file-editing tools (Write, Edit, MultiEdit,
```
with:
```bash
# NOTE: Worktree isolation for file-editing tools (Write, Edit,
```

- [ ] **Step 3: Fix worktree-guard.sh header comment (line 2)**

Edit `claude/.claude/hooks/worktree-guard.sh`, replace:
```bash
# PreToolUse hook (matchers: Write, Edit, MultiEdit, NotebookEdit):
```
with:
```bash
# PreToolUse hook (matchers: Write, Edit, NotebookEdit):
```

- [ ] **Step 4: Verify no MultiEdit remains in these two files and syntax is intact**

Run:
```bash
grep -n MultiEdit claude/.claude/hooks/git-safety.sh claude/.claude/hooks/worktree-guard.sh; echo "grep-rc=$?"
bash -n claude/.claude/hooks/git-safety.sh && bash -n claude/.claude/hooks/worktree-guard.sh && echo "syntax ok"
```
Expected: `grep-rc=1` (no matches), then `syntax ok`.

- [ ] **Step 5: Verify git-safety's own suite stays green**

Run:
```bash
bash claude/.claude/tests/commit-scope/run.sh | tail -1
```
Expected: `32 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/hooks/git-safety.sh claude/.claude/hooks/worktree-guard.sh
git commit -m "docs(claude): correct file-editing matcher comments"
```

---

## Task 2: Drop dead MultiEdit branches (C3 live)

`MultiEdit` was removed as a tool, so these branches never match. Removing them cannot change runtime output.

**Files:**
- Modify: `claude/.claude/hooks/permission-policy.sh:24`, `:40`
- Modify: `claude/.claude/hooks/failure-recovery.sh:64`
- Modify: `claude/.claude/hooks/audit-log.sh:27`

- [ ] **Step 1: permission-policy.sh fast-exit allowlist (line 24)**

Edit `claude/.claude/hooks/permission-policy.sh`, replace:
```bash
  Bash|Write|Edit|MultiEdit|NotebookEdit|WebFetch) ;;
```
with:
```bash
  Bash|Write|Edit|NotebookEdit|WebFetch) ;;
```

- [ ] **Step 2: permission-policy.sh edit-tool case (line 40)**

Replace:
```bash
  Write|Edit|MultiEdit|NotebookEdit)
```
with:
```bash
  Write|Edit|NotebookEdit)
```

- [ ] **Step 3: failure-recovery.sh file-tool regex (line 64)**

Edit `claude/.claude/hooks/failure-recovery.sh`, replace:
```bash
if [[ -z "$guidance" ]] && [[ "$TOOL_NAME" =~ ^(Write|Edit|MultiEdit)$ ]]; then
```
with:
```bash
if [[ -z "$guidance" ]] && [[ "$TOOL_NAME" =~ ^(Write|Edit)$ ]]; then
```

- [ ] **Step 4: audit-log.sh jq summary branch (line 27)**

Edit `claude/.claude/hooks/audit-log.sh`, replace:
```bash
   elif $tool == "Edit" or $tool == "MultiEdit" then "edit \($path)"
```
with:
```bash
   elif $tool == "Edit" then "edit \($path)"
```

- [ ] **Step 5: Verify no MultiEdit remains anywhere in hooks/lib, and syntax intact**

Run:
```bash
grep -rn MultiEdit claude/.claude/hooks claude/.claude/lib; echo "grep-rc=$?"
for f in permission-policy failure-recovery audit-log; do bash -n "claude/.claude/hooks/$f.sh" || echo "SYNTAX FAIL $f"; done; echo "syntax checked"
```
Expected: `grep-rc=1` (zero matches), `syntax checked` with no SYNTAX FAIL.

- [ ] **Step 6: Verify permission-policy suite stays green and audit-log jq still parses**

Run:
```bash
bash claude/.claude/tests/permission-policy/run.sh | tail -1
echo '{"tool_name":"Edit","session_id":"s","cwd":"/tmp","tool_input":{"file_path":"/tmp/x"}}' | bash claude/.claude/hooks/audit-log.sh; echo "audit-rc=$?"
```
Expected: `13 passed, 0 failed`, then `audit-rc=0` (hook runs without jq error).

- [ ] **Step 7: Commit**

```bash
git add claude/.claude/hooks/permission-policy.sh claude/.claude/hooks/failure-recovery.sh claude/.claude/hooks/audit-log.sh
git commit -m "refactor(claude): drop dead MultiEdit branches"
```

---

## Task 3: Add `cwd_repo_hint` helper + test harness + adopt (C1)

Introduces the `tests/session-lib/` harness (first helper), then dedups the
`.claude/worktrees/` repo-hint regex across 4 hooks.

**Files:**
- Create: `claude/.claude/tests/session-lib/run.sh`
- Create: `claude/.claude/tests/session-lib/helpers.sh`
- Create: `claude/.claude/tests/session-lib/cases/10-cwd-repo-hint-under-worktree.sh`
- Create: `claude/.claude/tests/session-lib/cases/11-cwd-repo-hint-outside.sh`
- Modify: `claude/.claude/lib/session.sh` (append helper after `check_worktree_pending`)
- Modify: `claude/.claude/hooks/git-session-start.sh:14-18`
- Modify: `claude/.claude/hooks/restore-git-context.sh:13-17`
- Modify: `claude/.claude/hooks/failure-recovery.sh:33-37`
- Modify: `claude/.claude/hooks/git-safety.sh:18-22`

- [ ] **Step 1: Create the test runner**

Create `claude/.claude/tests/session-lib/run.sh`:
```bash
#!/usr/bin/env bash
# session.sh lib test runner. Iterates cases/*.sh; each sources helpers.sh.
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_HOME="$HERE"
export LIB="$HERE/../../lib/session.sh"

[[ -f "$LIB" ]] || { echo "missing lib: $LIB" >&2; exit 2; }

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

- [ ] **Step 2: Create the shared test helpers**

Create `claude/.claude/tests/session-lib/helpers.sh`:
```bash
#!/usr/bin/env bash
# Sourced by every case. Provides assertions + git-fixture setup for session.sh.
set -uo pipefail

: "${LIB:?LIB must be set by run.sh}"

CASE_TMP="$(mktemp -d -t session-lib-test.XXXXXX)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# assert_eq <want> <got> [msg]
assert_eq() {
  local want="$1" got="$2" msg="${3:-assert_eq}"
  [[ "$got" == "$want" ]] || { echo "  $msg: want='$want' got='$got'" >&2; exit 1; }
}

# init_main_repo <dir> -- a primary working tree with one commit.
init_main_repo() {
  local dir="$1"
  ( cd "$dir" \
    && git init -q -b main \
    && git config user.email "test@example.com" \
    && git config user.name "Test" \
    && git config core.hooksPath /dev/null \
    && git commit -q --allow-empty -m "seed" )
}

# add_linked_worktree <repo> <wt> -- adds a linked worktree at <wt>.
add_linked_worktree() {
  local repo="$1" wt="$2"
  ( cd "$repo" && git worktree add -q -b feature "$wt" >/dev/null 2>&1 )
}
```

- [ ] **Step 3: Write the failing cases for `cwd_repo_hint`**

Create `claude/.claude/tests/session-lib/cases/10-cwd-repo-hint-under-worktree.sh`:
```bash
#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

fake="$CASE_TMP/myrepo/.claude/worktrees/wt1/sub"
mkdir -p "$fake"
got=$( cd "$fake" && source "$LIB" && cwd_repo_hint )
want=$( cd "$fake" && printf '%s' "${PWD%%/.claude/worktrees/*}" )
assert_eq "$want" "$got" "cwd_repo_hint under worktree"
```

Create `claude/.claude/tests/session-lib/cases/11-cwd-repo-hint-outside.sh`:
```bash
#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

plain="$CASE_TMP/plain/dir"
mkdir -p "$plain"
got=$( cd "$plain" && source "$LIB" && cwd_repo_hint )
assert_eq "" "$got" "cwd_repo_hint outside worktree path"
```

- [ ] **Step 4: Run the suite — expect FAIL**

Run:
```bash
bash claude/.claude/tests/session-lib/run.sh
```
Expected: both cases FAIL (`cwd_repo_hint: command not found` → non-zero), `0 passed, 2 failed`.

- [ ] **Step 5: Implement `cwd_repo_hint` in session.sh**

Edit `claude/.claude/lib/session.sh`, replace the final block:
```bash
  echo "  Emergency escape: rm \"${pf}\"" >&2
  exit 2
}
```
with:
```bash
  echo "  Emergency escape: rm \"${pf}\"" >&2
  exit 2
}

# --- Worktree / CWD detection ---

# Echo the parent repo path when PWD is (or was) under a .claude/worktrees/
# directory; echo nothing otherwise. Used to build the "! cd <repo>" recovery
# hint when a worktree CWD has been deleted.
cwd_repo_hint() {
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}
```

- [ ] **Step 6: Run the suite — expect PASS**

Run:
```bash
bash claude/.claude/tests/session-lib/run.sh | tail -1
```
Expected: `2 passed, 0 failed`.

- [ ] **Step 7: Adopt in git-session-start.sh (sources session.sh at top)**

Edit `claude/.claude/hooks/git-session-start.sh`, replace:
```bash
if [[ ! -d "$PWD" ]]; then
  repo_hint=""
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    repo_hint="${BASH_REMATCH[1]}"
  fi
```
with:
```bash
if [[ ! -d "$PWD" ]]; then
  repo_hint=$(cwd_repo_hint)
```

- [ ] **Step 8: Adopt in restore-git-context.sh (sources session.sh at top)**

Edit `claude/.claude/hooks/restore-git-context.sh`, replace:
```bash
if [[ ! -d "$PWD" ]]; then
  repo_hint=""
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    repo_hint="${BASH_REMATCH[1]}"
  fi
```
with:
```bash
if [[ ! -d "$PWD" ]]; then
  repo_hint=$(cwd_repo_hint)
```

- [ ] **Step 9: Adopt in failure-recovery.sh (sources session.sh at top)**

Edit `claude/.claude/hooks/failure-recovery.sh`, replace:
```bash
  repo_hint=""
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    repo_hint="${BASH_REMATCH[1]}"
  fi
  if [[ -n "$repo_hint" ]]; then
```
with:
```bash
  repo_hint=$(cwd_repo_hint)
  if [[ -n "$repo_hint" ]]; then
```

- [ ] **Step 10: Adopt in git-safety.sh (lazy-source inside the cold dead-CWD branch)**

Edit `claude/.claude/hooks/git-safety.sh`, replace:
```bash
if [[ ! -d "$PWD" ]]; then
  repo_hint=""
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    repo_hint="${BASH_REMATCH[1]}"
  fi
  {
```
with:
```bash
if [[ ! -d "$PWD" ]]; then
  # Cold path (deleted CWD): lazily source session.sh for cwd_repo_hint so the
  # hot path (~90% of Bash calls) stays lib-free.
  # shellcheck source=../lib/session.sh
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"
  repo_hint=$(cwd_repo_hint)
  {
```

- [ ] **Step 11: Verify all four hooks parse and existing suites stay green**

Run:
```bash
for f in git-session-start restore-git-context failure-recovery git-safety; do bash -n "claude/.claude/hooks/$f.sh" || echo "SYNTAX FAIL $f"; done; echo "syntax checked"
bash claude/.claude/tests/commit-scope/run.sh | tail -1
bash claude/.claude/tests/session-lib/run.sh | tail -1
```
Expected: `syntax checked` (no fails), `32 passed, 0 failed`, `2 passed, 0 failed`.

- [ ] **Step 12: Confirm git-safety's lazy-source line resolves to a real lib**

The dead-CWD branch is hard to reproduce reliably (it requires running from a
directory that no longer exists). Coverage rationale: the `cwd_repo_hint` unit
cases (10/11) prove the regex, and `bash -n` in Step 11 proves the lazy-source
line parses. Additionally confirm the sourced path is correct:

```bash
src=$(dirname "$(readlink -f claude/.claude/hooks/git-safety.sh)")/../lib/session.sh
[[ -f "$src" ]] && grep -q '^cwd_repo_hint' "$src" && echo "lazy-source target OK"
```
Expected: `lazy-source target OK`.

- [ ] **Step 13: Commit**

```bash
git add claude/.claude/lib/session.sh claude/.claude/tests/session-lib/run.sh claude/.claude/tests/session-lib/helpers.sh claude/.claude/tests/session-lib/cases/10-cwd-repo-hint-under-worktree.sh claude/.claude/tests/session-lib/cases/11-cwd-repo-hint-outside.sh claude/.claude/hooks/git-session-start.sh claude/.claude/hooks/restore-git-context.sh claude/.claude/hooks/failure-recovery.sh claude/.claude/hooks/git-safety.sh
git commit -m "refactor(claude): add cwd_repo_hint helper + adopt in 4 hooks"
```

---

## Task 4: Add `worktree_kind` helper + adopt (C2)

Dedups the absolute-git-dir vs git-common-dir comparison in `git-session-start.sh`
and `restore-git-context.sh`.

**Files:**
- Modify: `claude/.claude/lib/session.sh` (append after `cwd_repo_hint`)
- Create: `claude/.claude/tests/session-lib/cases/20-worktree-kind-none.sh`
- Create: `claude/.claude/tests/session-lib/cases/21-worktree-kind-main.sh`
- Create: `claude/.claude/tests/session-lib/cases/22-worktree-kind-linked.sh`
- Modify: `claude/.claude/hooks/git-session-start.sh:44`, `:76`
- Modify: `claude/.claude/hooks/restore-git-context.sh:38-40`, `:45`

- [ ] **Step 1: Write the failing cases for `worktree_kind`**

Create `claude/.claude/tests/session-lib/cases/20-worktree-kind-none.sh`:
```bash
#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

mkdir -p "$CASE_TMP/nogit"
got=$( cd "$CASE_TMP/nogit" && source "$LIB" && worktree_kind )
assert_eq "none" "$got" "worktree_kind outside a git repo"
```

Create `claude/.claude/tests/session-lib/cases/21-worktree-kind-main.sh`:
```bash
#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/mainrepo"
mkdir -p "$repo"
init_main_repo "$repo"
got=$( cd "$repo" && source "$LIB" && worktree_kind )
assert_eq "main" "$got" "worktree_kind in primary working tree"
```

Create `claude/.claude/tests/session-lib/cases/22-worktree-kind-linked.sh`:
```bash
#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

repo="$CASE_TMP/lrepo"
mkdir -p "$repo"
init_main_repo "$repo"
wt="$CASE_TMP/lrepo-wt"
add_linked_worktree "$repo" "$wt"
got=$( cd "$wt" && source "$LIB" && worktree_kind )
assert_eq "linked" "$got" "worktree_kind in a linked worktree"
```

- [ ] **Step 2: Run the suite — expect the 3 new cases to FAIL**

Run:
```bash
bash claude/.claude/tests/session-lib/run.sh
```
Expected: cases 10/11 PASS, cases 20/21/22 FAIL (`worktree_kind: command not found`), `2 passed, 3 failed`.

- [ ] **Step 3: Implement `worktree_kind` in session.sh**

Edit `claude/.claude/lib/session.sh`, replace:
```bash
cwd_repo_hint() {
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}
```
with:
```bash
cwd_repo_hint() {
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# Echo the worktree kind for the current directory:
#   linked  -- inside a linked (git worktree add) working tree
#   main    -- inside the primary working tree
#   none    -- not in a git repo, or a bare repo
worktree_kind() {
  git rev-parse --git-dir >/dev/null 2>&1 || { printf 'none'; return; }
  [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && { printf 'none'; return; }
  local abs common
  abs=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
  common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
  if [[ -n "$abs" && -n "$common" && "$abs" != "$common" ]]; then
    printf 'linked'
  else
    printf 'main'
  fi
}
```

- [ ] **Step 4: Run the suite — expect all PASS**

Run:
```bash
bash claude/.claude/tests/session-lib/run.sh | tail -1
```
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Adopt in git-session-start.sh — drop unused GIT_COMMON_DIR (line 44)**

`GIT_COMMON_DIR` is used only in the linked-worktree comparison; `GIT_ABS_DIR`
is still needed for the FETCH_HEAD path, so keep it. Edit
`claude/.claude/hooks/git-session-start.sh`, replace:
```bash
GIT_ABS_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
GIT_COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
```
with:
```bash
GIT_ABS_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
```

- [ ] **Step 6: Adopt in git-session-start.sh — use worktree_kind for the branch (line 76)**

Replace:
```bash
if [[ -n "$GIT_ABS_DIR" && -n "$GIT_COMMON_DIR" && "$GIT_ABS_DIR" != "$GIT_COMMON_DIR" ]]; then
```
with:
```bash
if [[ "$(worktree_kind)" == "linked" ]]; then
```

- [ ] **Step 7: Adopt in restore-git-context.sh — drop the two dir locals (lines 38-40)**

`BRANCH` is still used in the emitted context; the two dir vars are only used in
the comparison. Edit `claude/.claude/hooks/restore-git-context.sh`, replace:
```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
GIT_ABS_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
GIT_COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
```
with:
```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
```

- [ ] **Step 8: Adopt in restore-git-context.sh — use worktree_kind for the branch (line 45)**

Replace:
```bash
if [[ -n "$GIT_ABS_DIR" && -n "$GIT_COMMON_DIR" && "$GIT_ABS_DIR" != "$GIT_COMMON_DIR" ]]; then
```
with:
```bash
if [[ "$(worktree_kind)" == "linked" ]]; then
```

- [ ] **Step 9: Verify hooks parse, no stale var refs, suites green**

Run:
```bash
for f in git-session-start restore-git-context; do bash -n "claude/.claude/hooks/$f.sh" || echo "SYNTAX FAIL $f"; done
grep -n 'GIT_COMMON_DIR' claude/.claude/hooks/git-session-start.sh claude/.claude/hooks/restore-git-context.sh; echo "common-dir-rc=$?"
bash claude/.claude/tests/session-lib/run.sh | tail -1
```
Expected: no SYNTAX FAIL; `common-dir-rc=1` (no remaining `GIT_COMMON_DIR` references in either file); `5 passed, 0 failed`.

- [ ] **Step 10: Smoke-test restore-git-context preserves PostCompact behavior**

Run from the worktree root (a linked worktree):
```bash
printf '{}' | bash claude/.claude/hooks/restore-git-context.sh
```
Expected: JSON with a `systemMessage` field containing `worktree session active` and the current branch (confirms `worktree_kind` returns `linked` here and PostCompact still routes through `emit_context`'s `systemMessage`).

- [ ] **Step 11: Commit**

```bash
git add claude/.claude/lib/session.sh claude/.claude/tests/session-lib/cases/20-worktree-kind-none.sh claude/.claude/tests/session-lib/cases/21-worktree-kind-main.sh claude/.claude/tests/session-lib/cases/22-worktree-kind-linked.sh claude/.claude/hooks/git-session-start.sh claude/.claude/hooks/restore-git-context.sh
git commit -m "refactor(claude): add worktree_kind helper + adopt in 2 hooks"
```

---

## Task 5: Add `workflow_no_pr` helper + adopt (C5)

Centralizes the `CLAUDE_GIT_WORKFLOW == "no-pr"` gate. The MODE strings each hook
emits stay separate (stage-specific); only the gate is shared.

**Files:**
- Modify: `claude/.claude/lib/session.sh` (append after `worktree_kind`)
- Create: `claude/.claude/tests/session-lib/cases/30-workflow-no-pr-set.sh`
- Create: `claude/.claude/tests/session-lib/cases/31-workflow-no-pr-unset.sh`
- Modify: `claude/.claude/hooks/git-session-start.sh:156`
- Modify: `claude/.claude/hooks/restore-git-context.sh:47`, `:52`
- Modify: `claude/.claude/hooks/worktree-exited.sh:11`
- Modify: `claude/.claude/hooks/git-safety.sh:48` (pointer comment only)

- [ ] **Step 1: Write the failing cases for `workflow_no_pr`**

Create `claude/.claude/tests/session-lib/cases/30-workflow-no-pr-set.sh`:
```bash
#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

got=$( source "$LIB"; CLAUDE_GIT_WORKFLOW=no-pr; if workflow_no_pr; then echo yes; else echo no; fi )
assert_eq "yes" "$got" "workflow_no_pr when env=no-pr"
```

Create `claude/.claude/tests/session-lib/cases/31-workflow-no-pr-unset.sh`:
```bash
#!/usr/bin/env bash
source "$TEST_HOME/helpers.sh"

got=$( source "$LIB"; unset CLAUDE_GIT_WORKFLOW; if workflow_no_pr; then echo yes; else echo no; fi )
assert_eq "no" "$got" "workflow_no_pr when unset"

got2=$( source "$LIB"; CLAUDE_GIT_WORKFLOW=pr; if workflow_no_pr; then echo yes; else echo no; fi )
assert_eq "no" "$got2" "workflow_no_pr when env=other value"
```

- [ ] **Step 2: Run the suite — expect the 2 new cases to FAIL**

Run:
```bash
bash claude/.claude/tests/session-lib/run.sh
```
Expected: cases 10/11/20/21/22 PASS, 30/31 FAIL, `5 passed, 2 failed`.

- [ ] **Step 3: Implement `workflow_no_pr` in session.sh**

Edit `claude/.claude/lib/session.sh`, replace:
```bash
  if [[ -n "$abs" && -n "$common" && "$abs" != "$common" ]]; then
    printf 'linked'
  else
    printf 'main'
  fi
}
```
with:
```bash
  if [[ -n "$abs" && -n "$common" && "$abs" != "$common" ]]; then
    printf 'linked'
  else
    printf 'main'
  fi
}

# --- Workflow mode ---

# Return 0 when the session runs in no-pr workflow mode, 1 otherwise.
# Single source for the CLAUDE_GIT_WORKFLOW env-var name and its "no-pr"
# contract; a future rename or added mode changes only this function.
workflow_no_pr() {
  [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]
}
```

- [ ] **Step 4: Run the suite — expect all PASS**

Run:
```bash
bash claude/.claude/tests/session-lib/run.sh | tail -1
```
Expected: `7 passed, 0 failed`.

- [ ] **Step 5: Adopt in git-session-start.sh (line 156)**

Edit `claude/.claude/hooks/git-session-start.sh`, replace:
```bash
  if [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]; then
```
with:
```bash
  if workflow_no_pr; then
```

- [ ] **Step 6: Adopt in restore-git-context.sh (both occurrences, lines 47 and 52)**

Edit `claude/.claude/hooks/restore-git-context.sh`. There are two identical
lines; replace each occurrence of:
```bash
  if [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]; then
```
with:
```bash
  if workflow_no_pr; then
```
(Use replace-all for this file — both occurrences become `if workflow_no_pr; then`.)

- [ ] **Step 7: Adopt in worktree-exited.sh (line 11)**

Edit `claude/.claude/hooks/worktree-exited.sh`, replace:
```bash
if [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]; then
```
with:
```bash
if workflow_no_pr; then
```

- [ ] **Step 8: Add pointer comment in git-safety.sh (line 48)**

`git-safety.sh` keeps the inline check to protect its lib-free hot path. Edit
`claude/.claude/hooks/git-safety.sh`, replace:
```bash
# Per-repo opt-out of PR workflow.
NO_PR=false
[[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]] && NO_PR=true
```
with:
```bash
# Per-repo opt-out of PR workflow.
# Canonical gate: workflow_no_pr in lib/session.sh. Inlined here so the hot
# path (~90% of Bash calls) never sources a lib.
NO_PR=false
[[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]] && NO_PR=true
```

- [ ] **Step 9: Verify hooks parse; the inline gate remains only in git-safety; suites green**

Run:
```bash
for f in git-session-start restore-git-context worktree-exited git-safety; do bash -n "claude/.claude/hooks/$f.sh" || echo "SYNTAX FAIL $f"; done
grep -rn 'CLAUDE_GIT_WORKFLOW:-.*== "no-pr"' claude/.claude/hooks/
bash claude/.claude/tests/session-lib/run.sh | tail -1
bash claude/.claude/tests/commit-scope/run.sh | tail -1
bash claude/.claude/tests/permission-policy/run.sh | tail -1
```
Expected: no SYNTAX FAIL; the only remaining inline `== "no-pr"` match is in `git-safety.sh`; `7 passed, 0 failed`; `32 passed, 0 failed`; `13 passed, 0 failed`.

- [ ] **Step 10: Smoke-test the no-pr branch end-to-end**

Run from the worktree root:
```bash
CLAUDE_GIT_WORKFLOW=no-pr bash claude/.claude/hooks/worktree-exited.sh | grep -o 'requesting-code-review' && echo "no-pr branch OK"
CLAUDE_GIT_WORKFLOW= bash claude/.claude/hooks/worktree-exited.sh | grep -o 'wait for user to merge' && echo "pr branch OK"
```
Expected: `no-pr branch OK` and `pr branch OK` (gate routes both ways correctly).

- [ ] **Step 11: Commit**

```bash
git add claude/.claude/lib/session.sh claude/.claude/tests/session-lib/cases/30-workflow-no-pr-set.sh claude/.claude/tests/session-lib/cases/31-workflow-no-pr-unset.sh claude/.claude/hooks/git-session-start.sh claude/.claude/hooks/restore-git-context.sh claude/.claude/hooks/worktree-exited.sh claude/.claude/hooks/git-safety.sh
git commit -m "refactor(claude): add workflow_no_pr helper + adopt in 3 hooks"
```

---

## Final verification

- [ ] **All suites green, zero MultiEdit, helpers present**

Run:
```bash
grep -rn MultiEdit claude/.claude/hooks claude/.claude/lib; echo "multiedit-rc=$?"
bash claude/.claude/tests/session-lib/run.sh | tail -1
bash claude/.claude/tests/commit-scope/run.sh | tail -1
bash claude/.claude/tests/permission-policy/run.sh | tail -1
grep -c '^cwd_repo_hint\|^worktree_kind\|^workflow_no_pr' claude/.claude/lib/session.sh
```
Expected: `multiedit-rc=1` (none); `7 passed, 0 failed`; `32 passed, 0 failed`; `13 passed, 0 failed`; `3` (all helpers defined).

- [ ] **Understand the live-config boundary (no action)**

`~/.claude/` symlinks point at the MAIN checkout (`~/workspace/dotfiles/claude/.claude/...`),
not at this worktree. So these edits do NOT affect the live hooks until the
branch is merged to main and the main working tree contains them. The smoke
tests above exercise the worktree copies via relative paths, which is the
correct thing to verify here. No stow action is part of this plan; re-stowing
is unnecessary because the symlinks already exist and follow the main checkout.

---

## Notes for the implementer

- macOS ships bash 3.2; everything here is 3.2-safe (no associative arrays, `printf` over `echo -e`). `EPOCHSECONDS` is shimmed by `portability.sh`, sourced transitively via `session.sh`.
- Run all commands from the worktree root (`.claude/worktrees/hooks-cleanup-dedup`).
- The `git-safety.sh` commit-message guard and main-branch guard are active; all commits here are on the feature branch with explicit file staging, so they pass.
