# Permissions Auto Mode + Blanket MCP Allow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. NOTE: Per memory rule `feedback_subagent_mechanical_edits`, all tasks below have exact final code in the plan body. Apply edits directly from the orchestrator instead of dispatching implementer subagents. Final code-quality review at end.

**Goal:** Flip user-scope `defaultMode` to `auto` and allow all MCP server tools without prompting, with a CLAUDE.md note documenting the posture.

**Architecture:** Two single-line/two-line JSON edits in `claude/.claude/settings.base.json`, one markdown subsection insertion in the project root `CLAUDE.md`, then `claude-sync` regen after merge to main. No hook code changes. No overlay changes.

**Tech Stack:** JSON (`settings.base.json`), Markdown (`CLAUDE.md`), `jq` for verification, `claude-sync` shell script for regen.

---

## File Structure

- Modify: `claude/.claude/settings.base.json` (Task 1, Task 2 — same file, sequential)
- Modify: `CLAUDE.md` (Task 3 — project root, dotfiles repo)
- Run: `claude-sync` (Task 5 — post-merge, regenerates `~/.claude/settings.json`)
- Verify: `jq` query against `~/.claude/settings.json` (Task 5)

Spec reference: `docs/superpowers/specs/2026-05-22-permissions-auto-default-design.md`.

---

### Task 1: Flip `defaultMode` to `auto`

**Files:**
- Modify: `claude/.claude/settings.base.json` (line 9)

- [ ] **Step 1: Apply Edit**

Edit `claude/.claude/settings.base.json`:

OLD:
```
  "defaultMode": "acceptEdits",
```

NEW:
```
  "defaultMode": "auto",
```

- [ ] **Step 2: Verify JSON valid**

Run: `jq '.defaultMode' claude/.claude/settings.base.json`
Expected stdout: `"auto"`
Expected exit: 0.

- [ ] **Step 3: Commit**

```bash
git add claude/.claude/settings.base.json
git commit -m "feat(claude): default to auto permission mode for new sessions"
```

Commit body: optional. Keep subject only.

---

### Task 2: Replace specific MCP allow entries with `mcp__*` wildcard

**Files:**
- Modify: `claude/.claude/settings.base.json` (lines 39-40)

- [ ] **Step 1: Apply Edit**

Edit `claude/.claude/settings.base.json`:

OLD:
```
      "mcp__sequential-thinking__*",
      "mcp__qmd__*"
```

NEW:
```
      "mcp__*"
```

Note: the OLD block is unique in the file (no other lines with both
`mcp__sequential-thinking` and `mcp__qmd` adjacent). Indentation is six
spaces. Trailing comma on the FIRST line of OLD is preserved by leaving
it OUT of the replacement — the NEW single line has NO trailing comma
because it's the last entry in the `allow` array (followed by the
closing `]`).

- [ ] **Step 2: Verify JSON valid + wildcard present + specifics gone**

```bash
jq '.permissions.allow | map(select(startswith("mcp__")))' claude/.claude/settings.base.json
```

Expected stdout (JSON array, exactly):
```
[
  "mcp__*"
]
```

Expected exit: 0.

- [ ] **Step 3: Commit**

```bash
git add claude/.claude/settings.base.json
git commit -m "feat(claude): allow all MCP server tools via wildcard"
```

---

### Task 3: Add `## Permission posture` subsection to `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (project root, insert between line 55 and `# Brewfile rules` on line 57)

- [ ] **Step 1: Apply Edit**

Edit `CLAUDE.md` (project root):

OLD:
```
Run `claude-sync` after editing either file to regenerate `~/.claude/settings.json`.
The script deep-merges arrays (concatenate + deduplicate) and objects (overlay wins).
Without claude-skills cloned, it copies the base as-is.

# Brewfile rules
```

NEW:
```
Run `claude-sync` after editing either file to regenerate `~/.claude/settings.json`.
The script deep-merges arrays (concatenate + deduplicate) and objects (overlay wins).
Without claude-skills cloned, it copies the base as-is.

## Permission posture

User-scope defaults (in `claude/.claude/settings.base.json`):

- `defaultMode: "auto"` -- new sessions open in auto mode. A classifier
  judges unmatched tool calls; explicit `allow` entries skip the
  classifier. Requires Opus 4.6+ / Sonnet 4.6+ (Opus 4.7 in use).
- `permissions.allow: ["mcp__*", ...]` -- all MCP server tools skip the
  prompt path. Includes context-mode, qmd, sequential-thinking,
  Atlassian, Slack, Linear, Notion, claude.ai integrations, future
  servers.

Per-repo overrides live in `.claude/settings.local.json` (gitignored).
Add `permissions.ask` or `permissions.deny` rules there for sensitive
operations specific to that repo. Example:

```json
{
  "permissions": {
    "ask": [
      "mcp__claude_ai_Atlassian__*",
      "mcp__slack__slack_post_message"
    ]
  }
}
```

Local settings override base on a per-key basis (arrays concatenate).

# Brewfile rules
```

- [ ] **Step 2: Verify markdown renders + heading present**

```bash
grep -n "^## Permission posture$" CLAUDE.md
```

Expected stdout: a single line, e.g. `57:## Permission posture` (line
number depends on prior content; the heading must exist exactly once).
Expected exit: 0.

```bash
awk '/^# Claude Code settings/,/^# Brewfile rules/' CLAUDE.md | grep -c "Permission posture"
```

Expected stdout: `1` (the heading appears once inside the Claude Code
settings section).
Expected exit: 0.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): document permission posture for user-scope settings"
```

---

### Task 4: Final code-quality review

- [ ] **Step 1: Spec compliance pass**

Verify the three edits match the spec exactly. Read:
- `docs/superpowers/specs/2026-05-22-permissions-auto-default-design.md` sections E1, E2, E3.
- `git diff main..HEAD claude/.claude/settings.base.json CLAUDE.md`.

Confirm:
- E1: `defaultMode` is `"auto"`.
- E2: `permissions.allow` contains `"mcp__*"` and does NOT contain
  `"mcp__sequential-thinking__*"` or `"mcp__qmd__*"`.
- E3: `## Permission posture` subsection present with all bullet points
  from the spec.

- [ ] **Step 2: Atomicity check**

`git log --oneline main..HEAD` should show exactly three commits, one
per task (T1, T2, T3 in order). Each subject is one logical change.

- [ ] **Step 3: No unintended changes**

```bash
git diff main..HEAD --stat
```

Expected: exactly two files changed (`CLAUDE.md`,
`claude/.claude/settings.base.json`). No other paths.

If anything fails, fix inline before moving to Task 5.

---

### Task 5: Merge to main + regenerate `~/.claude/settings.json` + smoke verify

**Note:** This task runs AFTER Task 4 is clean. It is the
`finishing-a-development-branch` option 1 (no-pr mode) step.

- [ ] **Step 1: ExitWorktree(keep)**

Return to main worktree. Use the harness `ExitWorktree` tool with
`action: "keep"`.

- [ ] **Step 2: Merge branch to main (no-pr local merge)**

```bash
git checkout main
git merge --no-ff worktree-permissions-auto-default \
  -m "Merge branch 'worktree-permissions-auto-default'"
```

- [ ] **Step 3: Push main**

```bash
git push origin main
```

- [ ] **Step 4: Regenerate `~/.claude/settings.json`**

```bash
claude-sync
```

Expected stdout includes either:
- `settings.json: merged base + overlay -> /Users/ben/.claude/settings.json` (overlay present), OR
- `settings.json: copied base (no overlay found) -> /Users/ben/.claude/settings.json`.

- [ ] **Step 5: Verify generated file**

```bash
jq '.defaultMode' ~/.claude/settings.json
```
Expected: `"auto"`.

```bash
jq '.permissions.allow | map(select(startswith("mcp__")))' ~/.claude/settings.json
```
Expected output:
```
[
  "mcp__*"
]
```

(Overlay may add more `mcp__*`-prefix entries; verify the wildcard is
present and the two old specific entries are absent or harmless
duplicates eliminated by jq's `unique`-on-merge semantics in
claude-sync. If overlay re-adds specifics, dedup leaves both — that's
acceptable noise; the wildcard still wins precedence.)

- [ ] **Step 6: Remove worktree**

```bash
git worktree remove .claude/worktrees/permissions-auto-default
git branch -d worktree-permissions-auto-default
```

(Per the classifier-friction learning, run these as TWO separate Bash
calls rather than chaining with `&&`, in case the auto-mode classifier
flags the chained form.)

---

## Self-Review Checklist (orchestrator-side, after writing plan)

- [x] Spec coverage: E1 (Task 1), E2 (Task 2), E3 (Task 3). Verification
      covered by Task 4 + Task 5 Step 5.
- [x] Placeholder scan: no TBD/TODO. Each step contains exact OLD/NEW
      blocks or exact commands with expected output.
- [x] Type consistency: not applicable (JSON + markdown only). Field
      name `defaultMode` matches docs (camelCase). MCP rule syntax
      matches existing entries.
