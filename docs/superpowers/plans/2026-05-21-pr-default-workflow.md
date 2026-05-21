# PR-default workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flip documented canonical workflow tail from no-pr-default to PR-default; document no-pr as per-repo opt-in via `.claude/settings.local.json`.

**Architecture:** Doc-only changes. Hook code already implements PR-mode-by-default semantics (unset or non-`"no-pr"` env -> PR mode); only documentation in two files misaligns. Three edits to `claude/.claude/CLAUDE.md` and two edits to `claude/.claude/docs/superpowers-workflow.md`. No code, no settings, no tests changed.

**Tech Stack:** Markdown only. Verification via `grep`.

---

## File Structure

Files modified:
- `claude/.claude/CLAUDE.md` -- 3 edits (E1: workflow diagram, E2: no-pr section, E3: PR section)
- `claude/.claude/docs/superpowers-workflow.md` -- 2 edits (E4: feature-dev diagram, E5: notes bullet)

Files NOT touched:
- All hooks (`claude/.claude/hooks/*.sh`) -- semantics already correct
- `claude/.claude/settings.base.json` -- no env-var change
- `.claude/settings.local.json` (dotfiles repo) -- already `no-pr`, exemplifies opt-in
- `claude/.claude/docs/superpowers-workflow.md` debugging + quick-fix diagrams -- already mode-agnostic

All commits scoped `docs(claude)` per repo `git log` history.

---

## Task 1: CLAUDE.md canonical workflow code block (E1)

**Files:**
- Modify: `claude/.claude/CLAUDE.md` (canonical workflow code block tail, ~lines 74-77)

- [ ] **Step 1: Verify current state**

Run:
```bash
grep -n "no-pr default: option 1\|PR mode:       compound-engineering" claude/.claude/CLAUDE.md
```
Expected: matches found (current stale language present).

- [ ] **Step 2: Apply edit**

Replace this OLD content (exact text, inside the canonical workflow code fence):

```
finishing-a-development-branch
   ├─ no-pr default: option 1 (local merge -> push main)
   └─ PR mode:       compound-engineering:ce-commit-push-pr +
                     compound-engineering:ce-resolve-pr-feedback
```

With this NEW content:

```
finishing-a-development-branch
   ├─ PR mode (default):    option 2 (push + gh pr create)
   │                        receiving-code-review (reactive on feedback)
   │                        user merges via gh pr merge --merge
   └─ no-pr mode (opt-in):  option 1 (local merge -> push main)
```

- [ ] **Step 3: Verify edit applied**

Run:
```bash
grep -n "PR mode (default):    option 2\|no-pr mode (opt-in):  option 1" claude/.claude/CLAUDE.md
```
Expected: 2 matches (one for each line of the new diagram tail).

Run:
```bash
grep -n "no-pr default: option 1" claude/.claude/CLAUDE.md
```
Expected: zero matches (stale label gone from diagram).

Note: `ce-commit-push-pr` / `ce-resolve-pr-feedback` may still match in the
`### PR mode (opt-in)` body section -- those are removed in Task 3.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/CLAUDE.md
git commit -m "docs(claude): flip canonical workflow diagram to PR default"
```

---

## Task 2: CLAUDE.md "No-pr mode" section rename + env-var opt-in instructions (E2)

**Files:**
- Modify: `claude/.claude/CLAUDE.md` ("### No-pr mode (default)" section, ~lines 142-147)

- [ ] **Step 1: Verify current state**

Run:
```bash
grep -n "### No-pr mode (default)" claude/.claude/CLAUDE.md
```
Expected: 1 match.

- [ ] **Step 2: Apply edit**

Replace this OLD content:

```
### No-pr mode (default)

After implementation + `requesting-code-review` is clean +
`ce-compound` has documented the solution: invoke
`finishing-a-development-branch`, pick option 1 (local merge). Then
push main. No PR created.
```

With this NEW content:

```
### No-pr mode (opt-in)

Enable per repo by setting
`"env": {"CLAUDE_GIT_WORKFLOW": "no-pr"}` in that repo's
`.claude/settings.local.json`. The hook reads the env var; no other
config required. This dotfiles repo is the documented example.

After implementation + `requesting-code-review` is clean +
`ce-compound` has documented the solution: invoke
`finishing-a-development-branch`, pick option 1 (local merge). Then
push main. No PR created.
```

- [ ] **Step 3: Verify edit applied**

Run:
```bash
grep -n "### No-pr mode (opt-in)" claude/.claude/CLAUDE.md
```
Expected: 1 match.

Run:
```bash
grep -n 'CLAUDE_GIT_WORKFLOW.*no-pr' claude/.claude/CLAUDE.md
```
Expected: 1 match (in the new opt-in instruction line).

Run:
```bash
grep -n "### No-pr mode (default)" claude/.claude/CLAUDE.md
```
Expected: zero matches.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/CLAUDE.md
git commit -m "docs(claude): rename no-pr section to opt-in and document env var"
```

---

## Task 3: CLAUDE.md "PR mode" section rewrite (E3)

**Files:**
- Modify: `claude/.claude/CLAUDE.md` ("### PR mode (opt-in)" section, ~lines 149-167)

- [ ] **Step 1: Verify current state**

Run:
```bash
grep -n "### PR mode (opt-in)\|ce-commit-push-pr\|ce-resolve-pr-feedback" claude/.claude/CLAUDE.md
```
Expected: 3+ matches.

- [ ] **Step 2: Apply edit**

Replace this OLD content:

```
### PR mode (opt-in)

When a PR is needed:

- `compound-engineering:ce-commit-push-pr` -- commit, push, and open
  the PR with an adaptive value-first description (replaces older
  `/pr:create`).
- `compound-engineering:ce-resolve-pr-feedback` -- address review
  threads (replaces older `/pr:address`).
- After merge: `ExitWorktree("keep")` to return to main.
- YOU MUST use merge commits (`gh pr merge --merge`), never squash or
  rebase.
```

With this NEW content:

```
### PR mode (default)

After implementation + `requesting-code-review` is clean +
`ce-compound` has documented the solution: invoke
`finishing-a-development-branch`, pick option 2 (push +
`gh pr create`). The skill pushes the feature branch and opens the PR.

After PR creation:

- External reviewer feedback (if any) -> `receiving-code-review` ->
  fix -> push -> loop until clean.
- No external review -> proceed to merge.

Merge:

- YOU MUST use merge commits: `gh pr merge --merge`. Never squash,
  never rebase.
- After merge: `ExitWorktree("keep")` to return to main.
```

- [ ] **Step 3: Verify edit applied**

Run:
```bash
grep -n "### PR mode (default)" claude/.claude/CLAUDE.md
```
Expected: 1 match.

Run:
```bash
grep -n "receiving-code-review" claude/.claude/CLAUDE.md
```
Expected: 1+ matches.

Run:
```bash
grep -n "### PR mode (opt-in)\|ce-commit-push-pr\|ce-resolve-pr-feedback" claude/.claude/CLAUDE.md
```
Expected: zero matches.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/CLAUDE.md
git commit -m "docs(claude): rewrite PR section as default using superpowers skills"
```

---

## Task 4: superpowers-workflow.md feature-dev diagram tail (E4)

**Files:**
- Modify: `claude/.claude/docs/superpowers-workflow.md` (feature-dev code block tail, lines 24-27)

- [ ] **Step 1: Verify current state**

Run:
```bash
grep -n "no-pr default: option 1\|compound-engineering:ce-commit-push-pr\|compound-engineering:ce-resolve-pr-feedback" claude/.claude/docs/superpowers-workflow.md
```
Expected: 3 matches.

- [ ] **Step 2: Apply edit**

Replace this OLD content (note: arrows are unicode `→`, not `->`):

```
finishing-a-development-branch ← integrate
   ├─ no-pr default: option 1 (local merge → push main)
   └─ PR mode:       compound-engineering:ce-commit-push-pr
                     compound-engineering:ce-resolve-pr-feedback
```

With this NEW content:

```
finishing-a-development-branch ← integrate
   ├─ PR mode (default):    option 2 (push + gh pr create)
   │                        receiving-code-review (reactive on feedback)
   │                        user merges via gh pr merge --merge
   └─ no-pr mode (opt-in):  option 1 (local merge → push main)
```

- [ ] **Step 3: Verify edit applied**

Run:
```bash
grep -n "PR mode (default):    option 2\|no-pr mode (opt-in):  option 1" claude/.claude/docs/superpowers-workflow.md
```
Expected: 2 matches.

Run:
```bash
grep -n "no-pr default: option 1\|compound-engineering:ce-commit-push-pr\|compound-engineering:ce-resolve-pr-feedback" claude/.claude/docs/superpowers-workflow.md
```
Expected: zero matches.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/docs/superpowers-workflow.md
git commit -m "docs(claude): flip workflow doc diagram to PR default"
```

---

## Task 5: superpowers-workflow.md notes bullet (E5)

**Files:**
- Modify: `claude/.claude/docs/superpowers-workflow.md` (`finishing-a-development-branch` notes bullet, lines 110-114)

- [ ] **Step 1: Verify current state**

Run:
```bash
grep -n "Prefer option 1 for no-pr\|ce-commit-push-pr" claude/.claude/docs/superpowers-workflow.md
```
Expected: matches found.

- [ ] **Step 2: Apply edit**

Replace this OLD content:

```
- `finishing-a-development-branch` runs tests first; never proceeds if
  tests fail. Option 1 = local merge, option 2 = PR via `gh pr create`,
  option 3 = keep as-is, option 4 = discard. Prefer option 1 for no-pr
  mode; for PR mode, use `ce-commit-push-pr` instead of option 2 for
  richer descriptions.
```

With this NEW content:

```
- `finishing-a-development-branch` runs tests first; never proceeds if
  tests fail. Option 1 = local merge, option 2 = PR via `gh pr create`,
  option 3 = keep as-is, option 4 = discard. Use option 2 in PR mode
  (default); use option 1 in no-pr mode (opt-in). External PR-review
  feedback is handled reactively by `receiving-code-review`.
```

- [ ] **Step 3: Verify edit applied**

Run:
```bash
grep -n "Use option 2 in PR mode" claude/.claude/docs/superpowers-workflow.md
```
Expected: 1 match.

Run:
```bash
grep -n "receiving-code-review" claude/.claude/docs/superpowers-workflow.md
```
Expected: 2+ matches (skill name appears in this notes bullet and the post-`requesting-code-review` reference may already exist).

Run:
```bash
grep -n "Prefer option 1 for no-pr\|ce-commit-push-pr" claude/.claude/docs/superpowers-workflow.md
```
Expected: zero matches.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/docs/superpowers-workflow.md
git commit -m "docs(claude): rewrite finishing notes bullet for PR-default mode"
```

---

## Task 6: End-to-end verification

**Files:** None modified. Verification only.

- [ ] **Step 1: Stale-language sweep across both files**

Run:
```bash
grep -n "no-pr default\|No-pr mode (default)\|PR mode (opt-in)" \
  claude/.claude/CLAUDE.md \
  claude/.claude/docs/superpowers-workflow.md
```
Expected: zero matches across both files.

- [ ] **Step 2: Compound-engineering PR-flow refs sweep**

Run:
```bash
grep -n "ce-commit-push-pr\|ce-resolve-pr-feedback" \
  claude/.claude/CLAUDE.md \
  claude/.claude/docs/superpowers-workflow.md
```
Expected: zero matches.

- [ ] **Step 3: Confirm new language present in both files**

Run:
```bash
grep -c "PR mode (default)" claude/.claude/CLAUDE.md claude/.claude/docs/superpowers-workflow.md
```
Expected: each file >= 1.

Run:
```bash
grep -c "no-pr mode (opt-in)" claude/.claude/CLAUDE.md claude/.claude/docs/superpowers-workflow.md
```
Expected: each file >= 1.

Run:
```bash
grep -c "receiving-code-review" claude/.claude/CLAUDE.md claude/.claude/docs/superpowers-workflow.md
```
Expected: each file >= 1.

- [ ] **Step 4: Read both files end-to-end for internal consistency**

Open and read:
- `claude/.claude/CLAUDE.md` (the Git Workflow section, ~lines 50-170)
- `claude/.claude/docs/superpowers-workflow.md` (all)

Confirm:
- Canonical workflow diagrams in both files show PR-default tail first
- No-pr is consistently labeled "opt-in"
- PR-mode body in CLAUDE.md references `finishing-a-development-branch`
  option 2 (not `ce-commit-push-pr`)
- No-pr mode body in CLAUDE.md includes the env-var opt-in instruction
- Notes bullet in superpowers-workflow.md matches new mode labels

- [ ] **Step 5: Verify only docs modified (no hooks, no settings)**

Run:
```bash
git diff --name-only main..HEAD
```
Expected output (exact 3 files):
```
claude/.claude/CLAUDE.md
claude/.claude/docs/superpowers-workflow.md
docs/superpowers/specs/2026-05-21-pr-default-workflow-design.md
```

The plan file at `docs/superpowers/plans/2026-05-21-pr-default-workflow.md`
should also appear if not yet committed.

Run:
```bash
git diff --name-only main..HEAD | grep -E '^claude/.claude/hooks/|^claude/.claude/settings|^.claude/settings'
```
Expected: zero output (no hook or settings changes).

- [ ] **Step 6: No commit**

This task is verification only. No new files; no commit.
