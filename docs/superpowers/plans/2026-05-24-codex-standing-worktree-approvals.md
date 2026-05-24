# Codex Standing Worktree Approvals Implementation Plan

## Feature

Record standing user approvals for Codex worktree creation and isolated discard
cleanup in `codex/.codex/AGENTS.md`, without editing `CLAUDE.md`.

## Spec

`docs/superpowers/specs/2026-05-24-codex-standing-worktree-approvals-design.md`

## File Structure

- Modify: `codex/.codex/AGENTS.md`
  - Purpose: Codex-facing approval and worktree workflow instructions.
- Create: `docs/superpowers/plans/2026-05-24-codex-standing-worktree-approvals.md`
  - Purpose: Implementation plan for this workflow preference change.

## Task 1: Add Standing Approval Instructions

**Files:**

- Modify: `codex/.codex/AGENTS.md`

**Steps:**

- [ ] **Step 1: Locate the right insertion point**

  Use the existing `Subagent Approval Contract` and `Worktree Isolation`
  sections. The new text should live near those sections because it clarifies
  when Codex can proceed without asking.

- [ ] **Step 2: Add standing approval language**

  Add concise bullets that say:

  - Creating a linked worktree through `superpowers:using-git-worktrees` is
    standing user-approved for feature/change work when the current checkout is
    not already a linked worktree.
  - If `superpowers:brainstorming` is being used for work that may lead to repo
    edits, Codex should ensure a linked worktree exists before writing specs,
    plans, docs, or code.
  - Use the existing repository-local convention:
    `git worktree add .worktrees/<slug> -b <branch>`.
  - `finishing-a-development-branch` option 4 discard cleanup is standing
    user-approved only after the user has selected discard, and only for the
    confirmed isolated feature worktree/branch.

- [ ] **Step 3: Preserve approval boundaries**

  Ensure the text still says explicit approval is required for:

  - local merge-to-main;
  - push/PR paths outside the existing auto-review allowance;
  - force operations;
  - writes outside configured workspace roots;
  - unrelated branch/worktree deletion;
  - uncommitted changes;
  - unmerged user work that was not explicitly abandoned.

- [ ] **Step 4: Verify the diff**

  Run:

  ```bash
  git diff -- codex/.codex/AGENTS.md
  ```

  Expected: only `codex/.codex/AGENTS.md` changes, with no `CLAUDE.md` edit.

- [ ] **Step 5: Commit**

  Run:

  ```bash
  git add codex/.codex/AGENTS.md
  git commit -m "docs(codex): record standing worktree approvals"
  ```

## Task 2: Verify the Workflow Preference Change

**Files:**

- Inspect: `codex/.codex/AGENTS.md`
- Inspect: `CLAUDE.md`

**Steps:**

- [ ] **Step 1: Check required phrases**

  Verify `codex/.codex/AGENTS.md` mentions:

  - `superpowers:using-git-worktrees`;
  - `superpowers:brainstorming`;
  - `.worktrees/<slug>`;
  - `finishing-a-development-branch`;
  - option 4 discard cleanup;
  - explicit approval for local merge-to-main and push/PR paths outside the
    existing auto-review allowance.

- [ ] **Step 2: Confirm `CLAUDE.md` is untouched**

  Run:

  ```bash
  git diff --name-only main..HEAD
  ```

  Expected: includes `codex/.codex/AGENTS.md`, the approved spec, and this plan;
  does not include `CLAUDE.md`.

- [ ] **Step 3: Final status**

  Run:

  ```bash
  git status --short
  ```

  Expected: clean after the implementation commit.
