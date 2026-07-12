# Superpowers Spec Recap Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex summarize every written Superpowers brainstorming spec before asking the user to review and approve it.

**Architecture:** Add the enforceable behavior to the durable Codex instruction layer, then mirror the workflow expectation in the Superpowers workflow documentation. The change is documentation/instruction-only; there is no runtime code path.

**Tech Stack:** Markdown, Codex `AGENTS.md` instructions, Superpowers workflow documentation.

## Global Constraints

- Do not patch cached third-party Superpowers plugin files.
- Preserve the normal `superpowers:brainstorming` written-spec review gate before `superpowers:writing-plans`.
- Keep the recap concise and structured around spec path, goal, approach, key decisions, boundaries, and risks or tests.
- Apply the recap rule even when the design seems obvious.
- Stage explicit paths only when committing.

---

### Task 1: Add Durable Codex Instruction

**Files:**
- Modify: `codex/.codex/AGENTS.md`

**Interfaces:**
- Consumes: Existing `Default Implementation Workflow` section in `codex/.codex/AGENTS.md`.
- Produces: New `Superpowers Spec Review Workflow` section that future Codex sessions can follow.

- [ ] **Step 1: Confirm the target section context**

Run:

```bash
sed -n '20,70p' codex/.codex/AGENTS.md
```

Expected: output includes `## Default Implementation Workflow` followed by `## Worktree Isolation`.

- [ ] **Step 2: Add the spec recap rule**

Insert this section after `## Default Implementation Workflow` and before `## Worktree Isolation`:

```markdown
## Superpowers Spec Review Workflow

- After `superpowers:brainstorming` writes and self-reviews a design spec, include a concise summary of the spec before asking the user to review it.
- The summary should include the spec path, goal, recommended approach, key decisions, implementation boundaries or out-of-scope items, and main risks, validation points, or tests.
- Treat the summary as a review aid, not a replacement for the committed spec file.
- Preserve the normal written-spec review gate: wait for user approval or requested changes before invoking `superpowers:writing-plans`.
- Apply this rule even when the design seems obvious or the user likely does not need to read the full spec file.
```

- [ ] **Step 3: Verify the section is discoverable**

Run:

```bash
rg -n "Superpowers Spec Review Workflow|written-spec review gate|concise summary" codex/.codex/AGENTS.md
```

Expected: output shows the new heading and at least one rule line.

- [ ] **Step 4: Inspect the diff**

Run:

```bash
git diff -- codex/.codex/AGENTS.md
```

Expected: only the new `Superpowers Spec Review Workflow` section is added.

- [ ] **Step 5: Commit the instruction change**

Run:

```bash
git add codex/.codex/AGENTS.md
git diff --cached -- codex/.codex/AGENTS.md
git commit -m "docs(codex): require brainstorming spec recaps"
```

Expected: commit succeeds with only `codex/.codex/AGENTS.md` staged.

### Task 2: Document the Workflow Handoff

**Files:**
- Modify: `claude/.claude/docs/superpowers-workflow.md`

**Interfaces:**
- Consumes: Existing `Feature development` flow and `Notes` section in `claude/.claude/docs/superpowers-workflow.md`.
- Produces: Explanatory documentation that mirrors the durable Codex instruction.

- [ ] **Step 1: Confirm the workflow context**

Run:

```bash
sed -n '1,95p' claude/.claude/docs/superpowers-workflow.md
```

Expected: output includes the feature-development flow and `## Notes`.

- [ ] **Step 2: Update the feature-development flow annotation**

Change this line:

```text
    ↓                             → docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md
```

To:

```text
    ↓                             → docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md + recap
```

- [ ] **Step 3: Add the brainstorming recap note**

Add this bullet immediately after the existing `brainstorming` note in `## Notes`:

```markdown
- After `brainstorming` writes and self-reviews the design spec, Codex
  summarizes the spec before asking for review. The recap covers the
  spec path, goal, approach, key decisions, boundaries, and risks/tests;
  it is a review aid and does not replace the committed spec or approval
  gate.
```

- [ ] **Step 4: Verify the documentation mentions the recap handoff**

Run:

```bash
rg -n "design.md \\+ recap|summarizes the spec|review aid" claude/.claude/docs/superpowers-workflow.md
```

Expected: output shows the updated flow line and the new note.

- [ ] **Step 5: Inspect the final diff**

Run:

```bash
git diff -- claude/.claude/docs/superpowers-workflow.md
```

Expected: only the flow annotation and one explanatory note changed.

- [ ] **Step 6: Commit the workflow documentation change**

Run:

```bash
git add claude/.claude/docs/superpowers-workflow.md
git diff --cached -- claude/.claude/docs/superpowers-workflow.md
git commit -m "docs(workflow): document brainstorming spec recaps"
```

Expected: commit succeeds with only `claude/.claude/docs/superpowers-workflow.md` staged.

### Task 3: Verify the Whole Change

**Files:**
- Inspect: `codex/.codex/AGENTS.md`
- Inspect: `claude/.claude/docs/superpowers-workflow.md`
- Inspect: `docs/superpowers/specs/2026-07-12-superpowers-spec-recap-workflow-design.md`
- Inspect: `docs/superpowers/plans/2026-07-12-superpowers-spec-recap-workflow.md`

**Interfaces:**
- Consumes: Commits from Task 1 and Task 2.
- Produces: Verified instruction/documentation change ready for final review.

- [ ] **Step 1: Search all changed docs for the recap rule**

Run:

```bash
rg -n "Spec Review Workflow|spec recap|summarizes the spec|review aid|written-spec review gate" codex/.codex/AGENTS.md claude/.claude/docs/superpowers-workflow.md docs/superpowers/specs/2026-07-12-superpowers-spec-recap-workflow-design.md docs/superpowers/plans/2026-07-12-superpowers-spec-recap-workflow.md
```

Expected: output shows the durable instruction, workflow note, design spec, and plan references.

- [ ] **Step 2: Confirm there are no unresolved markers**

Run:

```bash
rg -n "UNRESOLVED_MARKER|NEEDS_DECISION|INCOMPLETE_SECTION" codex/.codex/AGENTS.md claude/.claude/docs/superpowers-workflow.md docs/superpowers/specs/2026-07-12-superpowers-spec-recap-workflow-design.md docs/superpowers/plans/2026-07-12-superpowers-spec-recap-workflow.md
```

Expected: no output.

- [ ] **Step 3: Confirm the branch history and working tree**

Run:

```bash
git log --oneline -4
git status --short
```

Expected: log includes the design commit, plan commit, and implementation commits; status is clean.

- [ ] **Step 4: Final review**

Read the final diffs and confirm:

```bash
git show --stat --oneline HEAD~3..HEAD
```

Expected: only the design spec, implementation plan, Codex instruction file, and workflow doc changed.
