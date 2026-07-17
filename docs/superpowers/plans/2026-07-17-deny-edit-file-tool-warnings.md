# Silence dead Write/NotebookEdit deny-rule warnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove 12 dead `Write(...)`/`NotebookEdit(...)` deny entries from `claude/.claude/settings.base.json` so Claude Code stops warning about them at startup.

**Architecture:** Claude Code matches all file-editing tools (Edit/Write/NotebookEdit) against `Edit(<path>)` deny rules only. Every flagged entry already has an `Edit(<path>)` sibling in the same `deny` block, so deleting the `Write`/`NotebookEdit` duplicates removes the warnings with zero protection loss. Regenerate the live `~/.claude/settings.json` via `claude-sync`.

**Tech Stack:** JSON (strict), `jq`, `claude-sync` script, GNU Stow layout.

## Global Constraints

- Edit only `claude/.claude/settings.base.json`. Do NOT touch the overlay, the generated `~/.claude/settings.json`, or per-repo local settings.
- Keep every `Read(<path>)`, `Edit(<path>)`, and `Bash(<glob>)` deny entry.
- File must remain valid strict JSON (no comments, no trailing commas).
- No behavior change: each deleted path must retain its `Edit(<path>)` sibling.

---

### Task 1: Delete the 12 dead deny entries

**Files:**
- Modify: `claude/.claude/settings.base.json` (deny array, lines ~52-81)

**Interfaces:**
- Consumes: nothing.
- Produces: a `deny` block whose only file-editing-tool entries are `Read(...)` and `Edit(...)`.

- [ ] **Step 1: Pre-check — confirm every target path has an `Edit(...)` sibling**

Run:
```bash
cd /Users/ben/workspace/dotfiles/.claude/worktrees/deny-edit-file-tool-warnings
for p in '**/.env' '**/.env.*' '~/.ssh/*' '~/.gnupg/*' '~/.aws/credentials' \
  '~/.claude/.credentials.json' '~/.kube/config' '~/.docker/config.json' \
  '~/.netrc' '~/.config/gh/hosts.yml'; do
  grep -qF "\"Edit($p)\"" claude/.claude/settings.base.json && echo "OK  Edit($p)" || echo "MISSING Edit($p)"
done
```
Expected: 10 lines, all starting `OK`. If any `MISSING`, stop — deletion would drop protection.

- [ ] **Step 2: Delete the 10 `Write(...)` entries**

Remove these exact lines from the `deny` array:

```
      "Write(**/.env)",
      "Write(**/.env.*)",
      "Write(~/.ssh/*)",
      "Write(~/.gnupg/*)",
      "Write(~/.aws/credentials)",
      "Write(~/.claude/.credentials.json)",
      "Write(~/.kube/config)",
      "Write(~/.docker/config.json)",
      "Write(~/.netrc)",
      "Write(~/.config/gh/hosts.yml)",
```

Leave the `Read(...)` and `Edit(...)` lines that surround them intact. Delete each `Write(...)` line entirely (including its trailing comma and newline) so no blank lines or dangling commas remain.

- [ ] **Step 3: Delete the 2 `NotebookEdit(...)` entries**

Remove these exact lines from the `deny` array:

```
      "NotebookEdit(**/.env)",
      "NotebookEdit(**/.env.*)",
```

- [ ] **Step 4: Verify no `Write(`/`NotebookEdit(` file-path entries remain**

Run:
```bash
grep -nE '"(Write|NotebookEdit)\(' claude/.claude/settings.base.json
```
Expected: no output (exit 1). Bash entries are unaffected — they use `Bash(...)`, not `Write(`/`NotebookEdit(`.

- [ ] **Step 5: Verify strict JSON validity**

Run:
```bash
jq . claude/.claude/settings.base.json > /dev/null && echo VALID
```
Expected: `VALID`.

- [ ] **Step 6: Confirm protection preserved — `Edit(...)` siblings still present**

Run:
```bash
grep -cE '"Edit\((\*\*/\.env|\*\*/\.env\.\*|~/\.ssh/\*|~/\.gnupg/\*|~/\.aws/credentials|~/\.claude/\.credentials\.json|~/\.kube/config|~/\.docker/config\.json|~/\.netrc|~/\.config/gh/hosts\.yml)\)"' claude/.claude/settings.base.json
```
Expected: `10`.

- [ ] **Step 7: Commit**

```bash
git add claude/.claude/settings.base.json
git commit -m "fix(claude): drop dead Write/NotebookEdit deny rules"
```

---

### Task 2: Regenerate the live settings and confirm warnings clear

**Files:**
- Generated (not committed): `~/.claude/settings.json`

**Interfaces:**
- Consumes: the edited `claude/.claude/settings.base.json` from Task 1.
- Produces: a regenerated `~/.claude/settings.json` whose `deny` block lacks the 12 entries.

- [ ] **Step 1: Run claude-sync**

Run:
```bash
claude-sync
```
Expected: completes without error (regenerates `~/.claude/settings.json` from base + overlay).

- [ ] **Step 2: Confirm the generated deny block dropped the entries and stays valid JSON**

Run:
```bash
jq -e '[.permissions.deny[] | select(test("^(Write|NotebookEdit)\\("))] | length == 0' ~/.claude/settings.json
```
Expected: `true`.

- [ ] **Step 3: Manual verification — restart clears the warnings**

Start a fresh Claude Code session (or restart the current one). Confirm the 12 `... is not matched by file permission checks ...` warnings no longer appear at startup.

This step is manual; there is no committable artifact. No commit for Task 2 (only generated, gitignored output changed).
