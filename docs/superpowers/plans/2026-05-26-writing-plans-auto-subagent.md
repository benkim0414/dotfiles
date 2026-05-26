# Writing-Plans Auto-Subagent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encode a user preference so that after `superpowers:writing-plans` saves a plan, the recommended execution skill (currently `superpowers:subagent-driven-development`) is auto-invoked without prompting the user.

**Architecture:** Two artefacts. (1) Add a directive paragraph to the user's global `claude/.claude/CLAUDE.md` (symlinked to `~/.claude/CLAUDE.md`) inside the "Canonical workflow" subsection so the instruction is loaded at session start. (2) Create a `feedback`-typed auto-memory file under the runtime memory dir and add an index line to `MEMORY.md`. No skill files are edited; both artefacts are durable across plugin upgrades.

**Tech Stack:** Markdown only. No code, no tests beyond manual behavioural verification. GNU Stow symlinks make the CLAUDE.md edit live immediately. Memory files are read by the harness on session start.

---

## File Structure

**Committed to dotfiles repo (this worktree branch):**

- Modify: `claude/.claude/CLAUDE.md` — append a short directive paragraph after the "Canonical workflow" diagram (between current line 99 `Full integration details:` and line 101 `### Commit rules`).

**Runtime files (NOT in dotfiles repo, written directly to live paths by the implementing agent):**

- Create: `/Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/feedback_writing_plans_auto_subagent.md` — feedback memory file.
- Modify: `/Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/MEMORY.md` — append one index line referencing the new feedback file.

Rationale for the split: the runtime memory dir lives outside the dotfiles repo (`/Users/ben/.claude/projects/...` is created by the harness per-project, not stowed). Confirmed during planning: `claude/.claude/projects/` does not exist in the repo. So the memory file is a runtime side effect, not a committed artefact. The CLAUDE.md edit is committed because that file IS stowed.

---

## Task 1: Add directive to CLAUDE.md "Canonical workflow" section

**Files:**

- Modify: `claude/.claude/CLAUDE.md` (insert between the current line 99 `Full integration details: ...` and the blank line that precedes `### Commit rules` at line 101)

- [ ] **Step 1: Re-read the insertion site to confirm line offsets**

Run:

```bash
sed -n '95,102p' claude/.claude/CLAUDE.md
```

Expected output (line numbers added here for clarity, not in the file):

```
95   │   │                        user merges via gh pr merge --merge
96   │   └─ no-pr mode (opt-in):  option 1 (local merge -> push main)
97   ```
98   (blank)
99   Full integration details: `~/.claude/docs/superpowers-workflow.md`
100  (blank)
101  ### Commit rules
```

If the line numbers have drifted (e.g. because earlier commits in the worktree changed them), find the new offsets with:

```bash
grep -n "Full integration details\|^### Commit rules" claude/.claude/CLAUDE.md
```

Use the actual offsets for the Edit in Step 2.

- [ ] **Step 2: Insert the directive paragraph**

Use the Edit tool. Match the exact lines as they exist (do not include line numbers). Replace this block:

```
Full integration details: `~/.claude/docs/superpowers-workflow.md`

### Commit rules
```

with this block:

```
Full integration details: `~/.claude/docs/superpowers-workflow.md`

### Execution handoff after `writing-plans`

When `superpowers:writing-plans` finishes saving the plan and reaches its
"Execution Handoff" section, do NOT prompt the user with the "Which
approach?" question. Auto-invoke whichever option the skill marks as
recommended (currently `superpowers:subagent-driven-development`).
Announce the choice in one line ("Auto-invoking
`subagent-driven-development` per user preference") and proceed.

Override: if the user explicitly asks for inline execution or names
`superpowers:executing-plans` in the same turn, honour that request
instead.

### Commit rules
```

Why this exact wording:

- "Whichever option the skill marks as recommended" tracks the
  recommendation rather than hard-coding the skill name, so a future
  plugin update that changes the recommended option does not invalidate
  the directive.
- The one-line announcement preserves visibility — the user can still
  see which skill is being invoked.
- The override clause keeps the user's escape hatch explicit.

- [ ] **Step 3: Verify the edit landed correctly**

Run:

```bash
grep -n "Execution handoff after" claude/.claude/CLAUDE.md
sed -n '/Execution handoff after/,/### Commit rules/p' claude/.claude/CLAUDE.md
```

Expected: one match for the heading; the printed range begins with the
new heading, contains the directive paragraph and the override clause,
and ends at `### Commit rules`. The override clause must mention
`superpowers:executing-plans` literally.

- [ ] **Step 4: Confirm the live symlink reflects the edit**

The dotfiles repo edits `claude/.claude/CLAUDE.md`. GNU Stow symlinks
`~/.claude/CLAUDE.md` -> `<repo>/claude/.claude/CLAUDE.md`. Confirm:

```bash
readlink /Users/ben/.claude/CLAUDE.md
grep -c "Execution handoff after" /Users/ben/.claude/CLAUDE.md
```

Expected: `readlink` prints a path containing `dotfiles/claude/.claude/CLAUDE.md`. The grep prints `1`.

If the grep prints `0`, the symlink is pointing at the main worktree's copy, not this feature worktree's copy. This is expected — the symlink in `~/.claude/` resolves to the primary checkout, not to a worktree path. Note this in the task notes and continue; the edit will take effect once the feature branch is merged back to main. No further action required during the worktree session.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/CLAUDE.md
git commit -m "docs(claude-md): auto-invoke recommended skill after writing-plans"
```

Scope `claude-md` is correct here: it names the affected component (the global CLAUDE.md instructions), not the artefact directory.

---

## Task 2: Create the feedback memory file

**Files:**

- Create: `/Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/feedback_writing_plans_auto_subagent.md`

This file lives outside the dotfiles repo and is NOT committed. The implementing agent writes it once; it persists in the runtime memory store.

- [ ] **Step 1: Confirm the memory directory exists**

Run:

```bash
ls -d /Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory
```

Expected: the path is printed (directory exists). It was verified during planning. If it is missing, stop and ask the user — the harness is responsible for creating per-project memory directories and a missing one is a signal that something is off.

- [ ] **Step 2: Write the memory file**

Use the Write tool with this exact content:

```markdown
---
name: writing-plans-auto-subagent
description: Auto-invoke the writing-plans recommended execution skill (currently superpowers:subagent-driven-development) without prompting the user
metadata:
  type: feedback
---

After `superpowers:writing-plans` saves a plan and reaches its
"Execution Handoff" section, skip the "Which approach?" prompt and
auto-invoke whichever option the skill marks as recommended
(currently `superpowers:subagent-driven-development`).

**Why:** The user has consistently selected option 1 (recommended) in
every prior session. The prompt adds friction without adding decision
value. Confirmed during 2026-05-26 brainstorm: the user's exact
phrasing was "the recommended skill between those two skills seems
always correct to me".

**How to apply:** When `writing-plans` finishes saving the plan,
announce the choice in one line ("Auto-invoking
`subagent-driven-development` per user preference") and proceed
directly into that skill. Do not present the multiple-choice question.

If the user explicitly asks for inline execution or names
`superpowers:executing-plans` in the same turn, honour the override
instead — the preference applies only to the default path, not to
explicit overrides.

Related: [[plan-artifacts-in-worktree]],
[[subagent-mechanical-edits]].
```

- [ ] **Step 3: Verify the file landed**

Run:

```bash
ls -la /Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/feedback_writing_plans_auto_subagent.md
head -7 /Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/feedback_writing_plans_auto_subagent.md
```

Expected: `ls` prints the file size in bytes (non-zero). `head` prints the YAML frontmatter block with `name`, `description`, and `type: feedback`.

- [ ] **Step 4: No commit**

This file is outside the dotfiles repo. Do not attempt to `git add` it from the worktree. Skip the commit step for this task.

---

## Task 3: Append index entry to MEMORY.md

**Files:**

- Modify: `/Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/MEMORY.md`

Like the file in Task 2, this is a runtime file. Not committed.

- [ ] **Step 1: Read the current index**

Run:

```bash
cat /Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/MEMORY.md
```

Expected: a small markdown file (no frontmatter) containing one-line bullet entries, each in the form
`- [Title](file.md) -- one-line hook`.

- [ ] **Step 2: Append the new index line**

Use the Edit tool on the MEMORY.md file. Find the last bullet line in the file and append a new line immediately after it. The new line is:

```
- [Auto-invoke recommended skill after writing-plans](feedback_writing_plans_auto_subagent.md) -- skip "Which approach?" prompt, use the option writing-plans marks as recommended (today: subagent-driven-development)
```

Keep the line under ~150 characters per the global memory rules. If the line exceeds 150 chars, shorten the hook portion (after the `--`) until it fits, but do not change the title or filename.

- [ ] **Step 3: Verify the index update**

Run:

```bash
grep -n "feedback_writing_plans_auto_subagent" /Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/MEMORY.md
wc -l /Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/MEMORY.md
awk '{ if (length > 200) print NR": "length" chars" }' /Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/MEMORY.md
```

Expected: `grep` prints exactly one match (the new index line). `wc -l` is one greater than the count seen in Step 1. `awk` prints no output (no line exceeds 200 chars, the truncation limit per the global memory rules).

- [ ] **Step 4: No commit**

Same reason as Task 2 Step 4 — file is outside the dotfiles repo. Skip the commit.

---

## Task 4: Verify the worktree commit state

- [ ] **Step 1: Confirm the worktree has exactly two commits ahead of main**

Run:

```bash
git log --oneline main..HEAD
```

Expected: two commits ahead of `main`:

1. `docs(claude-md): design auto-invoke recommended execution skill` (spec commit, created during brainstorming)
2. `docs(claude-md): auto-invoke recommended skill after writing-plans` (created in Task 1, Step 5)

The plan commit (this file) will be added separately by the writing-plans skill once the user approves the plan, so it may appear here too. Either way, all commits in this range must be on the `claude-md` scope.

- [ ] **Step 2: Confirm no runtime files were accidentally staged**

Run:

```bash
git status
```

Expected: clean working tree. The runtime memory files (Tasks 2 and 3) must NOT appear in `git status` because they live outside the dotfiles repo's working tree. If they do appear, something is wrong — stop and investigate before continuing.

---

## Task 5: Manual behavioural verification (post-merge)

This task cannot be executed inside the worktree. It is documented here so the user knows what to run after `finishing-a-development-branch` completes the merge into main.

- [ ] **Step 1: Start a fresh Claude Code session in the dotfiles repo root**

The session must start fresh so the harness re-reads `~/.claude/CLAUDE.md` and the memory index.

- [ ] **Step 2: Run a small brainstorm-then-plan flow**

Pick any trivial change (e.g., "add a comment to Brewfile explaining the alphabetical-sort rule"). Run brainstorming, then writing-plans.

- [ ] **Step 3: Confirm auto-invocation**

Expected behaviour at the end of `writing-plans`:

- The skill writes the plan file and prints the "Plan complete and saved..." line.
- Instead of the "Which approach? 1 / 2" question, the session prints one line such as `Auto-invoking subagent-driven-development per user preference.`
- The next tool call is the Skill invocation of `superpowers:subagent-driven-development`.

If the prompt still appears, the directive did not take effect. Check:

1. `cat ~/.claude/CLAUDE.md | grep -c "Execution handoff after"` — should print `1`.
2. `ls ~/.claude/projects/-Users-ben-workspace-dotfiles/memory/feedback_writing_plans_auto_subagent.md` — should exist.

If both checks pass but the prompt still appears, the user should report this back so the directive wording can be tightened.

- [ ] **Step 4: Confirm the override still works**

In a separate session, run brainstorm → writing-plans and explicitly say "use executing-plans for this one". Expected: `executing-plans` is invoked, not `subagent-driven-development`. This confirms the override clause is read and respected.

---

## Notes for the executor

- Task ordering matters: do Task 1 first so the dotfiles repo commit is clean and isolated. Tasks 2 and 3 produce no commits, so they can be done in either order after Task 1.
- The plan deliberately has no automated tests. Markdown directives cannot be unit-tested. The behavioural verification in Task 5 is the only validation, and it requires a fresh session.
- Do not edit the cached skill file at
  `~/.claude/plugins/cache/superpowers-marketplace/superpowers/<version>/skills/writing-plans/SKILL.md`. The spec explicitly rules this out — plugin upgrades would overwrite any edit there.
