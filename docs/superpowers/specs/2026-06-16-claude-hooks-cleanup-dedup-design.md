# Claude Hooks — Cleanup + Dedup Design

**Date:** 2026-06-16
**Status:** Approved for planning
**Scope:** `claude/.claude/hooks/`, `claude/.claude/lib/`, `claude/.claude/tests/`

## Problem

A full audit of the 13 Claude Code hooks found no orphaned or unused hook
files — every hook is registered in `settings.base.json` and fires on a live
event. But two classes of debt exist:

1. **Dead code from the removed `MultiEdit` tool** — 7 references across 5
   hooks. The tool name never arrives, so live branches never match and
   comments misdescribe reality.
2. **Copy-pasted logic across critical-path hooks** — the CWD-deleted-worktree
   detection (4 copies) and the linked-vs-main worktree detection (2 copies).

3. **Duplicated no-pr workflow gate** — the identical check
   `[[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]` appears in 4 hooks. The
   solution doc `env-driven-default-doc-drift-2026-05-22.md` flagged this
   single-equality-check pattern as a fragility source.

Nothing needs deleting wholesale. This is targeted cleanup of code we are
already maintaining.

## Historical-session findings

Mined `docs/solutions/`, full git fix/revert history on hooks, and 119 session
transcripts for hook issues not visible in the current tree.

- **No unaddressed runtime bug.** Transcript scan surfaced no hook-breakage
  signal. Every historical hook fix is already merged into current code.
- **Regression guard — do not undo these merged fixes during dedup:**
  - PostCompact uses `systemMessage` (not `additionalContext`) — `hookSpecificOutput`
    rejects `PostCompact` as an event name. Encapsulated in `emit_context`; the
    `restore-git-context` dedup must keep routing through it.
  - `restore-git-context` bare-repo guard + CWD health check + 10s timeout.
  - Numeric guards on mtime comparisons; `@tsv` stdin parse separator (avoid
    IFS whitespace collapsing).
  The new `worktree_kind` helper already reproduces the bare-repo guard, so
  `restore-git-context` keeps that behavior after adoption.
- **Live finding folded in as C5** — the duplicated no-pr gate (below).

## Audit result (reference)

| # | Hook | Event | Verdict |
|---|------|-------|---------|
| 1 | `git-session-start.sh` | SessionStart | needs improvement (C1, C2, C5) |
| 2 | `resolve-pr-refs.sh` | UserPromptSubmit | healthy |
| 3 | `read-once.sh` | PreToolUse | healthy (own lib + 18 tests) |
| 4 | `git-safety.sh` | PreToolUse(Bash) | needs improvement (C1, C3, C4) |
| 5 | `worktree-guard.sh` | PreToolUse(Write\|Edit\|NotebookEdit) | needs improvement (C4) |
| 6 | `permission-policy.sh` | PreToolUse | needs improvement (C3) |
| 7 | `notify.sh` | PreToolUse + Notification | healthy |
| 8 | `worktree-entered.sh` | PostToolUse(EnterWorktree) | healthy |
| 9 | `worktree-exited.sh` | PostToolUse(ExitWorktree) | needs improvement (C5) |
| 10 | `audit-log.sh` | PostToolUse | needs improvement (C3) |
| 11 | `failure-recovery.sh` | PostToolUseFailure | needs improvement (C1, C3) |
| 12 | `restore-git-context.sh` | PostCompact | needs improvement (C1, C2, C5) |
| 13 | `read-once-gc.sh` | SessionEnd | healthy |

"No longer used" hooks: **none**. "Unnecessary" hooks: **none**.

## Goals

- Remove all dead `MultiEdit` references (comments + live branches).
- Correct matcher-description comments that no longer match `settings.base.json`.
- Extract the three duplicated logic blocks (CWD repo-hint, worktree-kind
  detection, no-pr gate) into `lib/session.sh` helpers, with behavior preserved
  exactly.
- Add a test harness for the three new lib helpers, following the existing
  `commit-scope` / `permission-policy` test convention.

## Non-goals (YAGNI)

- No deletion or merging of any hook.
- No change to `read-once.*` (healthy, well-tested).
- No consolidation of cleanup ownership (`git-session-start` cache-prune vs
  `read-once-gc`) — that was the rejected "full restructure" approach.
- No change to `notify.sh` dual-context handling.
- No behavioral change to any hook. Output strings, exit codes, and matched
  shapes stay identical.

## Design

### C3 — MultiEdit removal (zero behavioral change)

Remove the dead tool from all 7 sites:

- `git-safety.sh:5`, `:53` — comments. Drop `MultiEdit`.
- `worktree-guard.sh:2` — comment. Fix to the real matcher (see C4).
- `permission-policy.sh:24`, `:40` — live case branches. Drop `MultiEdit` from
  the alternation; `Bash|Write|Edit|NotebookEdit|WebFetch` and
  `Write|Edit|NotebookEdit` respectively.
- `failure-recovery.sh:64` — live regex `^(Write|Edit|MultiEdit)$` →
  `^(Write|Edit)$`.
- `audit-log.sh:27` — jq branch `$tool == "Edit" or $tool == "MultiEdit"` →
  `$tool == "Edit"`.

These branches are unreachable today, so removal cannot change runtime output.

### C4 — Matcher-comment drift

`git-safety.sh:5` and `worktree-guard.sh:2` describe the file-editing matcher as
`Write|Edit|MultiEdit|NotebookEdit`. The actual registration in
`settings.base.json` is `Write|Edit|NotebookEdit`. Update both comments to match.

### C1 — `cwd_repo_hint` helper

The dead-CWD blocks in `git-safety`, `git-session-start`, `restore-git-context`,
and `failure-recovery` each recompute the same regex:

```bash
if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
  repo_hint="${BASH_REMATCH[1]}"
fi
```

Add to `lib/session.sh`:

```bash
# Echo the parent repo path when PWD is (or was) under a .claude/worktrees/
# directory; echo nothing otherwise. Used to build the "! cd <repo>" recovery
# hint when a worktree CWD has been deleted.
cwd_repo_hint() {
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}
```

Each caller keeps its own surrounding `[[ ! -d "$PWD" ]]` guard and its own
unique message (BLOCKED+exit 2, `emit_context_with_msg`, `emit_context`, or
`guidance` var). Only the regex is shared, via `repo_hint=$(cwd_repo_hint)`.

**`git-safety.sh` fast-path constraint:** `git-safety.sh` intentionally sources
no lib on its hot path (~90% of Bash calls are non-git). Its dead-CWD check sits
at the top, before any sourcing. To use the helper without regressing the hot
path, source `session.sh` **lazily inside the `[[ ! -d "$PWD" ]]` branch** — a
cold error path that only runs when a worktree CWD was deleted. The hot path
stays lib-free.

### C2 — `worktree_kind` helper

`git-session-start.sh` and `restore-git-context.sh` both run the same trio and
branch on it:

```bash
GIT_ABS_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
GIT_COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
# linked worktree if GIT_ABS_DIR != GIT_COMMON_DIR
```

Add to `lib/session.sh`:

```bash
# Echo the worktree kind for the current directory:
#   linked  -- inside a linked (git worktree add) working tree
#   main    -- inside the primary working tree
#   none    -- not in a git repo, or a bare repo
# Mirrors the absolute-git-dir vs git-common-dir comparison both callers use.
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

Callers that still need `BRANCH` / `GIT_ABS_DIR` for other purposes (e.g.
`git-session-start` uses `GIT_ABS_DIR` for the FETCH_HEAD path) keep computing
those locally; `worktree_kind` only replaces the linked-vs-main branch decision.
This keeps the extraction behavior-preserving rather than forcing all callers
through one signature.

### C5 — `workflow_no_pr` gate helper

Four hooks gate no-pr behavior on the identical equality check. The MODE
*strings* they emit differ per hook (stage-appropriate guidance) and stay
separate — only the gate is shared. Add to `lib/session.sh`:

```bash
# Return 0 when the session runs in no-pr workflow mode, 1 otherwise.
# Single source for the CLAUDE_GIT_WORKFLOW env-var name and its "no-pr"
# contract; a future rename or added mode changes only this function.
workflow_no_pr() {
  [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]
}
```

Adopt in the 3 hooks that already source `session.sh` at top:

- `git-session-start.sh:156` → `if workflow_no_pr; then`
- `restore-git-context.sh:47,52` → `if workflow_no_pr; then`
- `worktree-exited.sh:11` → `if workflow_no_pr; then`

`git-safety.sh:48` keeps its inline `NO_PR=true` assignment — adopting the
helper there would force an early `session.sh` source and regress the lib-free
hot path (same constraint as C1). The inline one-liner is self-documenting; a
comment points to `workflow_no_pr` as the canonical definition.

### Test harness

No shared test harness exists for `session.sh` today (`commit-scope` and
`permission-policy` each have their own under `claude/.claude/tests/`). Add
`claude/.claude/tests/session-lib/` with a `run.sh` + `cases/` mirroring the
existing convention, covering all three new helpers. Cases:

- `cwd_repo_hint` returns the parent repo when `PWD` is under
  `.../.claude/worktrees/<name>/...`.
- `cwd_repo_hint` returns empty when `PWD` is outside a worktrees path.
- `worktree_kind` returns `none` outside a git repo.
- `worktree_kind` returns `main` in a primary working tree.
- `worktree_kind` returns `linked` in a `git worktree add` tree.
- `workflow_no_pr` returns 0 when `CLAUDE_GIT_WORKFLOW=no-pr`.
- `workflow_no_pr` returns 1 when the env var is unset or any other value.

`shellcheck` is not installed locally, so lint is a manual/CI concern; the spec
does not add a lint gate.

## Risk & verification

- C3/C4 are comment edits and removal of unreachable branches — no runtime
  effect. Verified by re-running the existing `permission-policy` (13) suite,
  which exercises `permission-policy.sh`'s matcher.
- C1/C2 touch four critical-path hooks. Verification: the existing suites stay
  green (`permission-policy` 13/0, `commit-scope` 32/0, `read-once` cases), the
  new `session-lib` suite passes, and a manual smoke of each touched hook with a
  representative JSON payload reproduces its prior output byte-for-byte.

## Files touched

- Edit: `git-safety.sh`, `git-session-start.sh`, `restore-git-context.sh`,
  `failure-recovery.sh`, `worktree-guard.sh`, `permission-policy.sh`,
  `audit-log.sh`, `worktree-exited.sh`
- Edit: `claude/.claude/lib/session.sh` (add `cwd_repo_hint`, `worktree_kind`,
  `workflow_no_pr`)
- New: `claude/.claude/tests/session-lib/run.sh` + `cases/`

## Commit decomposition (atomicity)

Expected split (one logical change each). Scope is `claude` on every commit:
in this repo each top-level Stow package is the component, and `claude/` is the
package these files live in. `git log` confirms `(claude)` is the dominant
scope on hook/lib files (138 commits, vs `hooks` 22). `hooks`, `session`,
`read-once`, `permission-policy` are subdir/artifact names, not components —
not used as scopes here.

1. `refactor(claude): drop dead MultiEdit references` (C3)
2. `docs(claude): correct file-editing matcher comments` (C4)
3. `refactor(claude): add cwd_repo_hint helper + adopt in 4 hooks` (C1)
4. `refactor(claude): add worktree_kind helper + adopt in 2 hooks` (C2)
5. `refactor(claude): add workflow_no_pr helper + adopt in 3 hooks` (C5)
6. `test(claude): add session-lib helper test harness`
