# Detach Stale claude-skills Settings Overlay — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Claude Code prompting on non-destructive Atlassian MCP operations by removing the stale claude-skills overlay from the `claude-sync` merge, leaving `settings.base.json` + the dotfiles company overlay as the sole authority for MCP verb gating.

**Architecture:** `claude-sync` generates `~/.claude/settings.json` by folding `settings.base.json` with discovered overlays (string arrays concatenate + dedupe). The claude-skills overlay re-introduces broad `ask` globs (`create/update/edit/add/transition/invoke`) that `ask`-beats-`allow` precedence then enforces over the company `mcp__atlassian__*` allow. The merge cannot subtract, so the fix removes the overlay from discovery entirely.

**Tech Stack:** Bash, `jq`, GNU Stow.

## Global Constraints

- Editing happens in the worktree at `bin/.local/bin/claude-sync` and `CLAUDE.md` (repo root).
- Staging: `git add <path>` only — never `git add -A`/`.`/`-u`, never `git commit -a`/`-am` (hook-enforced).
- Two atomic commits: the script fix, then the doc update (code + repo-root doc are distinct logical changes).
- Destructive verb set is unchanged: base keeps `delete/remove/sync/deploy/apply/patch/write` in `ask`.
- The merge `jq` logic in `claude-sync` is NOT modified — line 57 already reduces over the overlay array, which works for length 1.

---

### Task 1: Detach claude-skills overlay from `claude-sync`

**Files:**
- Modify: `bin/.local/bin/claude-sync` (header comment lines 4-8; variable lines 20, 23; append line 40)

**Interfaces:**
- Consumes: nothing (entry point).
- Produces: a regenerated `~/.claude/settings.json` whose `permissions.ask` no longer contains the non-destructive verb globs.

- [ ] **Step 1: Update the header comment block to describe a single overlay**

Replace lines 4-8 (current):

```bash
# Base settings:   $DOTFILES/claude/.claude/settings.base.json      (always present)
# Overlays (in merge order, later wins on scalar conflict):
#   1. $DOTFILES/claude/.claude/settings.overlay.json              (company, optional)
#   2. $CLAUDE_SKILLS_DIR/settings.overlay.json                    (claude-skills, optional)
# Output:          ~/.claude/settings.json                          (generated, not a symlink)
```

with:

```bash
# Base settings:   $DOTFILES/claude/.claude/settings.base.json      (always present)
# Overlay:         $DOTFILES/claude/.claude/settings.overlay.json   (company, optional)
# Output:          ~/.claude/settings.json                          (generated, not a symlink)
```

- [ ] **Step 2: Remove the `SKILLS` variable (line 20)**

Delete this line:

```bash
SKILLS="${CLAUDE_SKILLS_DIR:-$HOME/workspace/claude-skills}"
```

- [ ] **Step 3: Remove the `SKILLS_OVERLAY` variable (line 23)**

Delete this line:

```bash
SKILLS_OVERLAY="$SKILLS/settings.overlay.json"
```

- [ ] **Step 4: Remove the claude-skills overlay append (line 40)**

Delete this line:

```bash
[[ -f "$SKILLS_OVERLAY" ]]   && overlays+=("$SKILLS_OVERLAY")
```

After this edit the discovery block reads:

```bash
overlays=()
[[ -f "$DOTFILES_OVERLAY" ]] && overlays+=("$DOTFILES_OVERLAY")
```

- [ ] **Step 5: Verify the script still parses**

Run: `bash -n bin/.local/bin/claude-sync`
Expected: no output, exit 0.

- [ ] **Step 6: Confirm no dangling references to the removed variables**

Run: `grep -nE 'SKILLS\b|SKILLS_OVERLAY|CLAUDE_SKILLS_DIR' bin/.local/bin/claude-sync || echo "clean"`
Expected: `clean` (no matches).

- [ ] **Step 7: Regenerate live settings and assert the fix**

Run:

```bash
claude-sync >/dev/null
jq -r '
  def has_glob($re): (.permissions.ask // []) | map(select(test($re))) | length;
  "create-class ask globs (want 0): \(has_glob("\\*(create|update|edit|add|transition|invoke)\\*"))",
  "atlassian allow present (want true): \((.permissions.allow // []) | any(. == "mcp__atlassian__*"))",
  "base destructive delete ask present (want true): \((.permissions.ask // []) | any(. == "mcp__*__*delete*"))"
' ~/.claude/settings.json
```

Expected output:

```
create-class ask globs (want 0): 0
atlassian allow present (want true): true
base destructive delete ask present (want true): true
```

- [ ] **Step 8: Confirm intended policy still holds via the hermetic test**

Run: `bash claude/.claude/tests/mcp-permission-overlay/run.sh`
Expected: ends with `mcp-permission-overlay: all passed` (exit 0). This test merges base + company overlay only, so it is unaffected by the script change but confirms the policy the regenerated file now matches.

- [ ] **Step 9: Commit**

```bash
git add bin/.local/bin/claude-sync
git commit -m "fix(claude-sync): detach stale claude-skills settings overlay

The claude-skills overlay re-added broad ask globs (create/update/edit/
add/transition/invoke). ask beats allow and the merge only concatenates,
so the company mcp__atlassian__* allow could never suppress them and every
non-destructive Atlassian call prompted. Drop the overlay from discovery;
base + company overlay become the sole MCP verb-gating authority.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Update CLAUDE.md layered-merge documentation

**Files:**
- Modify: `CLAUDE.md:100-113` ("Claude Code settings (layered merge)" section)

**Interfaces:**
- Consumes: the detachment from Task 1.
- Produces: documentation matching the single-overlay reality.

- [ ] **Step 1: Rewrite the layered-merge section**

Replace lines 102-113 (current):

```markdown
Base settings live in `claude/.claude/settings.base.json`. Overlays are
folded on top in order (later wins on scalar conflict):

1. `claude/.claude/settings.overlay.json` -- company overlay, committed
   to this repo (e.g. atlassian/slack MCP auto-allow). Always applies.
2. `~/workspace/claude-skills/settings.overlay.json` -- claude-skills
   overlay, optional. Merges when the repo is cloned.

Run `claude-sync` after editing any of them to regenerate
`~/.claude/settings.json`. The script deep-merges arrays (concatenate +
deduplicate) and objects (overlay wins). With no overlay present it
copies the base as-is.
```

with:

```markdown
Base settings live in `claude/.claude/settings.base.json`. A single
overlay is folded on top (later wins on scalar conflict):

1. `claude/.claude/settings.overlay.json` -- company overlay, committed
   to this repo (e.g. atlassian/slack MCP auto-allow). Always applies.

Run `claude-sync` after editing either of them to regenerate
`~/.claude/settings.json`. The script deep-merges arrays (concatenate +
deduplicate) and objects (overlay wins). With no overlay present it
copies the base as-is.

The `~/workspace/claude-skills/settings.overlay.json` overlay was detached
on 2026-06-30: it carried stale broad `ask` globs
(`create/update/edit/add/transition/invoke`) that re-gated Atlassian
non-destructive MCP tools. Because `ask` beats `allow` and the merge only
concatenates (it cannot subtract), the company `mcp__atlassian__*` allow
could not suppress them. Base + company overlay are now the sole authority
for MCP verb gating.
```

- [ ] **Step 2: Verify the claude-skills overlay is no longer presented as an active layer**

Run: `sed -n '100,120p' CLAUDE.md | grep -n 'claude-skills'`
Expected: the only match is the "was detached on 2026-06-30" explanatory line (no numbered active-overlay entry).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude-sync): record claude-skills overlay detachment

Document the single-overlay layering and why the claude-skills overlay was
removed from the merge.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Spec change 1 (claude-sync detach) → Task 1. ✓
- Spec change 2 (CLAUDE.md rewrite) → Task 2. ✓
- Spec change 3 (regenerate + verify) → Task 1 Steps 7-8. ✓
- Consequence "session restart required" → surfaced post-implementation (see note below), not a code task. ✓
- Consequence "claude-skills hooks dropped" → accepted in spec, no task. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"/vague steps. Every edit shows exact before/after text. ✓

**Type consistency:** N/A (shell + markdown); variable names (`SKILLS`, `SKILLS_OVERLAY`, `DOTFILES_OVERLAY`) match the file read verbatim. ✓

## Post-Implementation Note

After both commits, `~/.claude/settings.json` is already regenerated (Task 1 Step 7). **Running Claude Code sessions must be restarted** to load the new permission rules — including the `ops` repo session that surfaced the original prompt. Permission rules are read at session start.
