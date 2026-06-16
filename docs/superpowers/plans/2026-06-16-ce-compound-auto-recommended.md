# ce-compound auto-pick recommended options Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CLAUDE.md directive so Claude auto-selects the recommended option for every ce-compound interactive prompt instead of asking.

**Architecture:** Single-file documentation edit to `claude/.claude/CLAUDE.md` (stowed to `~/.claude/CLAUDE.md`). User instructions override skill behavior, so the ce-compound skill file is untouched. New `### Execution handoff for ce-compound` subsection placed after the `### Execution handoff after writing-plans` subsection and before `### Commit rules`.

**Tech Stack:** Markdown, GNU Stow symlink.

---

### Task 1: Add the ce-compound execution-handoff directive

**Files:**
- Modify: `claude/.claude/CLAUDE.md` (insert between the `writing-plans` handoff and `### Commit rules`)

- [ ] **Step 1: Insert the new subsection**

Anchor: the line `same turn (e.g. "use executing-plans for this one", "dispatch` ... ending `honour that request instead.` immediately precedes `### Commit rules`. Insert the following block on its own, after that paragraph and before `### Commit rules`:

```markdown
### Execution handoff for `ce-compound`

When `compound-engineering:ce-compound` reaches any interactive blocking
prompt, do NOT ask. Auto-select the recommended option, announce the choice
in one line, then proceed. Mirrors the `writing-plans` handoff above.
(Headless mode already skips these prompts -- this covers interactive runs.)

Prompt-by-prompt:

1. **Full vs Lightweight** -> always **Full**, the option the skill marks
   `(recommended)`.
2. **Session history** (Full only) -> the skill marks no recommendation, so
   pick per-run and state which. Default to **skipping** (the skill flags
   added time + token cost); opt in only when the documented problem clearly
   spans multiple prior sessions and that history would materially improve
   the doc.
3. **Discoverability Check consent** -> if the check finds a gap, apply the
   smallest fitting edit directly; if not, move on. No prompt either way.
4. **"What's next?" menu** -> auto-pick **only in no-pr repos**. Detect mode
   from the git-workflow session context / `CLAUDE_GIT_WORKFLOW=no-pr`.
   - **no-pr mode**: pick option 1 **Continue workflow** (skill-marked
     `(recommended)`) -> proceed to `finishing-a-development-branch`
     option 1 (local merge).
   - **PR mode (default)**: present the menu normally -- do NOT auto-select.
     Pushing + opening a PR is outward-facing; the user controls that step.

Announce in one line, e.g. `Auto-running ce-compound Full, skipping session
history, applying discoverability edit, continuing workflow per user
preference.` (drop the "continuing workflow" clause in PR-mode repos).

Override: if the user names a different choice in the same turn (e.g. "use
lightweight", "search session history", "stop after the doc"), honour that
instead.
```

- [ ] **Step 2: Verify the symlink resolves and the section renders**

Run: `grep -n "Execution handoff for \`ce-compound\`" ~/.claude/CLAUDE.md`
Expected: one match (confirms the stowed symlink picks up the worktree... note: symlink points to MAIN worktree's claude/.claude/CLAUDE.md, so this match appears only after merge to main). During worktree work, verify against the worktree file instead:
Run: `grep -n "Execution handoff for" claude/.claude/CLAUDE.md`
Expected: two matches -- the existing `writing-plans` one and the new `ce-compound` one.

- [ ] **Step 3: Commit**

```bash
git add claude/.claude/CLAUDE.md
git commit -m "docs(claude): auto-pick recommended ce-compound prompts"
```

---

## Self-Review

- **Spec coverage:** All four prompts (Full/Lightweight, session history, Discoverability, What's next) covered; no-pr gating on prompt 4 covered; override clause covered. No gaps.
- **Placeholder scan:** None -- the full directive text is inline.
- **Type consistency:** N/A (documentation change).
