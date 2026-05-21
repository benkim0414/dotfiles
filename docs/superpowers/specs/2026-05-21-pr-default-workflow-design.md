# PR workflow as default

Date: 2026-05-21
Branch: worktree-pr-default-workflow

## Problem

Docs (`claude/.claude/CLAUDE.md` + `claude/.claude/docs/superpowers-workflow.md`)
describe `no-pr` as the default workflow tail. Hooks already implement the
inverse: unset or non-`"no-pr"` env value triggers PR mode (strict main-branch
protection, silent MODE block); only `CLAUDE_GIT_WORKFLOW=no-pr` activates
no-pr mode. Doc/hook intent mismatch.

Goal: flip documented default so PR mode is the canonical tail, no-pr is
explicit per-repo opt-in via `.claude/settings.local.json` `env` block. This
dotfiles repo continues opt-in to `no-pr`; its `.claude/settings.local.json`
becomes the documented example.

## Non-goals

- Hook code changes. Existing semantics already correct.
- `settings.base.json` changes.
- This repo's `.claude/settings.local.json` value change (stays `no-pr`).
- Repo-level `CLAUDE.md` (dotfiles root) changes. No mode refs.
- Removing compound-engineering skills. They remain installed; just demoted
  from default doc references in favor of superpowers equivalents.

## Decisions

### D1: PR-mode MODE-block emission

Hooks stay silent in PR mode (no `MODE: pr` context block injected at session
start or after compaction). Default is the implicit unset case. Only `no-pr`
opt-in emits a verbose MODE reminder.

Rationale: minimize context noise on every session start. PR mode is the
canonical path; reminder unnecessary.

### D2: Pre-PR review only (canonical superpowers)

Per `superpowers:requesting-code-review` SKILL.md, mandatory triggers are
"after each subagent task, after major feature, **before merge to main**".
In PR mode, merge happens via the PR, so the pre-merge review pass runs
**before** `finishing-a-development-branch` option 2 creates the PR. No
post-PR review loop.

External reviewer feedback (if any) is handled reactively by
`superpowers:receiving-code-review`. Not a mandatory step.

### D3: ce-compound runs in worktree, before PR creation

User-specified: ce-compound is the **last** in-worktree step. Solution doc
lands at `docs/solutions/<...>.md` on the feature branch; merges to main
with the PR.

Ordering: ce-compound runs AFTER pre-PR requesting-code-review loop is
clean, BEFORE `finishing-a-development-branch` option 2 push + PR create.

### D4: PR creation via superpowers, not compound-engineering

`superpowers:finishing-a-development-branch` option 2 (`gh pr create`) is
the canonical PR creation step. Drop references to
`compound-engineering:ce-commit-push-pr` and
`compound-engineering:ce-resolve-pr-feedback` from default flow docs.
Compound skills remain available for ad-hoc use; just not the documented
default.

### D5: Merge style stays merge commits

Existing rule: `gh pr merge --merge`. Never squash, never rebase. User
performs merge manually after review.

## Canonical flow (PR mode = default)

```
EnterWorktree → brainstorming → writing-plans →
subagent-driven-development (requesting-code-review after EACH task) →
verification-before-completion →
requesting-code-review (final pre-merge pass; loop until clean) →
ce-compound (last in-worktree step) →
finishing-a-development-branch option 2 (push + gh pr create) →
[wait for external review or self-merge]
   ↓ if external feedback:
   receiving-code-review → fix → push → loop until clean
   ↓
user merges PR (gh pr merge --merge) →
ExitWorktree("keep")
```

## No-pr opt-in flow

Enable per-repo: set `"env": {"CLAUDE_GIT_WORKFLOW": "no-pr"}` in that
repo's `.claude/settings.local.json`. Hooks read env var; no other
config required.

```
EnterWorktree → brainstorming → writing-plans →
subagent-driven-development →
verification-before-completion →
requesting-code-review (loop until clean) →
ce-compound →
finishing-a-development-branch option 1 (local merge → push main) →
ExitWorktree("keep")
```

## Files changed

### 1. `claude/.claude/CLAUDE.md`

Three edits:

**E1: Canonical workflow code block (around line 60-77)**

Replace existing tail (`finishing-a-development-branch ├─ no-pr default ...`)
with PR-mode-default tail showing pre-PR review → ce-compound → finishing
option 2 → reactive receiving-code-review → user merge → ExitWorktree.

**E2: Rename "No-pr mode (default)" section to "No-pr mode (opt-in)"**
(around line 142-147)

Update body to include opt-in instruction:

> Enable per repo by setting `"env": {"CLAUDE_GIT_WORKFLOW": "no-pr"}` in
> that repo's `.claude/settings.local.json`. This dotfiles repo is an
> example.

Keep existing behavior description (option 1, local merge, push main).

**E3: Rename "PR mode (opt-in)" section to "PR mode (default)"**
(around line 159-167)

Rewrite body:
- pre-PR `requesting-code-review` (loop clean)
- `ce-compound` (last in-worktree step)
- `finishing-a-development-branch` option 2 (push + `gh pr create`)
- Reactive `receiving-code-review` if external feedback
- User merges with `gh pr merge --merge`
- `ExitWorktree("keep")`

Remove references to `ce-commit-push-pr` and `ce-resolve-pr-feedback`.

### 2. `claude/.claude/docs/superpowers-workflow.md`

**E4: Feature-dev flow diagram (lines ~5-29)**

Replace `finishing-a-development-branch ├─ no-pr default ... └─ PR mode ...`
tail with new PR-default tail mirroring CLAUDE.md E3 + no-pr opt-in branch.

**E5: Notes section "finishing-a-development-branch" bullet (lines ~108-114)**

Rewrite: PR mode (default) uses option 2; no-pr mode (opt-in) uses option 1.
Remove `ce-commit-push-pr` recommendation.

**E6: No change to debugging + quick-fix diagrams**

Confirmed mode-agnostic in current doc (lines ~56-72, ~84-88). Both end at
`finishing-a-development-branch` without specifying mode tail. The flow
diagrams inherit the mode branch from the feature-dev section. No edit
required.

**E7: "When each skill fires" table (lines ~40-50)**

No change. Each row is mode-agnostic. `finishing-a-development-branch` row
already reads "All gates passed, ready to integrate" — covers both modes.

### 3. `.claude/settings.local.json` (this repo)

No change. Already `"env": {"CLAUDE_GIT_WORKFLOW": "no-pr"}`. Becomes
documented opt-in example.

## Verification

- Read both edited docs end-to-end for internal consistency.
- `grep -n "no-pr default\|PR opt-in\|PR mode (opt-in)\|No-pr mode (default)"
  claude/.claude/CLAUDE.md claude/.claude/docs/superpowers-workflow.md` →
  zero matches.
- `grep -n "ce-commit-push-pr\|ce-resolve-pr-feedback"
  claude/.claude/CLAUDE.md claude/.claude/docs/superpowers-workflow.md` →
  zero matches (compound skills no longer default-referenced).
- No code change; no test suite to run. Hook behavior unchanged.
- Manual sanity: start fresh Claude session in a directory without
  `CLAUDE_GIT_WORKFLOW=no-pr` env. Confirm no `MODE: no-pr` context block
  injected. Confirm `git-safety.sh` still blocks merge/push to main
  (PR-mode strict enforcement).

## Out of scope

- Auto-detecting PR-mode vs no-pr from repo signals (e.g., presence of
  `gh` remote). Env var stays the single source of truth.
- Adding a `pr` explicit env value. Unset = PR mode is sufficient.
- Migration script to flip other repos. User handles per-repo as needed.
- `claude-sync` regeneration. Files are stowed directly to `~/.claude/`;
  no generated artifact involved.
