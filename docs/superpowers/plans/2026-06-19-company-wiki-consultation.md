# Company Wiki Consultation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude consult the company `wiki` qmd collection for relevant company knowledge during tasks, with all wiki config isolated in the company layer (overlay + a separate imported instructions file), distinct from personal defaults.

**Architecture:** Three homes, each correct for its content. (1) qmd read-tool permissions go in the company overlay `settings.overlay.json`. (2) The "when to consult the wiki" directive goes in a new stowed `CLAUDE.company.md`, imported into the personal `CLAUDE.md` via a native `@CLAUDE.company.md` line. (3) Trigger is instruction-only — no hooks. qmd MCP server and the wiki index already exist and are unchanged.

**Tech Stack:** Claude Code layered settings (`claude-sync` jq merge), GNU Stow, `@import` CLAUDE.md syntax, qmd 2.1.0 MCP (`mcp__qmd__{query,get,multi_get,status}`), bash test harness.

---

## File structure

All paths relative to repo root (the worktree).

- `claude/.claude/CLAUDE.company.md` — CREATE. Company instructions, incl. the wiki-consultation directive.
- `claude/.claude/CLAUDE.md` — MODIFY. Add a "Company configuration" section with `@CLAUDE.company.md`.
- `claude/.claude/settings.overlay.json` — MODIFY. Add four qmd read tools to `allow`.
- `claude/.claude/tests/mcp-permission-overlay/run.sh` — MODIFY. Assert qmd read tools resolve to `allow`, and an unlisted qmd tool falls to `classifier`.
- `CLAUDE.md` (repo root) — MODIFY. Document the qmd-wiki overlay posture and the `CLAUDE.company.md` import mechanism.

---

## Task 1: Auto-allow qmd read tools (overlay) — test-first

**Files:**
- Test: `claude/.claude/tests/mcp-permission-overlay/run.sh`
- Modify: `claude/.claude/settings.overlay.json`

- [ ] **Step 1: Extend the overlay test with qmd expectations (failing)**

In `claude/.claude/tests/mcp-permission-overlay/run.sh`, replace this block:

```bash
expect mcp__slack__slack_add_reaction              allow

# Bucket C (destructive) -> ask
```

with:

```bash
expect mcp__slack__slack_add_reaction              allow

# qmd company-wiki read tools auto-allowed via the company overlay
expect mcp__qmd__query                             allow
expect mcp__qmd__get                               allow
expect mcp__qmd__multi_get                         allow
expect mcp__qmd__status                            allow
# only the four named read tools are allow-listed; anything else qmd
# exposes falls to the auto-mode classifier (no blanket qmd allow)
expect mcp__qmd__some_other_tool                   classifier

# Bucket C (destructive) -> ask
```

- [ ] **Step 2: Run the test to verify the qmd-allow cases fail**

Run: `bash claude/.claude/tests/mcp-permission-overlay/run.sh`
Expected: FAIL — the four `mcp__qmd__{query,get,multi_get,status}` lines report `-> classifier (want allow)`; the final line `mcp__qmd__some_other_tool -> classifier` already passes; overall `mcp-permission-overlay: FAILURES`.

- [ ] **Step 3: Add the qmd read tools to the overlay allow list**

In `claude/.claude/settings.overlay.json`, replace:

```json
    "allow": [
      "mcp__atlassian__*",
      "mcp__slack__*"
    ],
```

with:

```json
    "allow": [
      "mcp__atlassian__*",
      "mcp__slack__*",
      "mcp__qmd__query",
      "mcp__qmd__get",
      "mcp__qmd__multi_get",
      "mcp__qmd__status"
    ],
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash claude/.claude/tests/mcp-permission-overlay/run.sh`
Expected: PASS — all lines `ok`, final line `mcp-permission-overlay: all passed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/tests/mcp-permission-overlay/run.sh claude/.claude/settings.overlay.json
git commit -m "feat(claude): auto-allow qmd wiki read tools in company overlay"
```

---

## Task 2: Add company wiki-consultation instructions

**Files:**
- Create: `claude/.claude/CLAUDE.company.md`
- Modify: `claude/.claude/CLAUDE.md` (after the H1, before `## Preferences`)

- [ ] **Step 1: Create `claude/.claude/CLAUDE.company.md`**

Full file content:

```markdown
# Company configuration

Company-specific Claude Code instructions. Kept separate from personal
defaults in `CLAUDE.md`; imported from there via `@CLAUDE.company.md`.

## Company knowledge (qmd `wiki` collection)

The company knowledge base lives at `~/workspace/wiki` and is indexed by qmd
as the `wiki` collection (an OKF bundle: decisions, patterns, projects,
solutions, components, entities, sources).

- At the START of any non-trivial task, and whenever the topic shifts, run one
  `mcp__qmd__query` against collection `wiki` describing the task. Prefer
  lex + vec sub-queries; always set `intent`.
- When starting work in or about a project, query the wiki for that project's
  decisions and conventions before planning or implementing.
- Pull full documents with `mcp__qmd__get` when a hit is directly relevant.
- This is read-only company reference. Never run `qmd collection add`,
  `qmd embed`, or `qmd update` -- indexing is a manual user action.
```

- [ ] **Step 2: Add the import to the personal `claude/.claude/CLAUDE.md`**

Replace:

```markdown
# Global Claude Code Preferences

## Preferences
```

with:

```markdown
# Global Claude Code Preferences

## Company configuration

Company-wide instructions (distinct from these personal defaults) live in a
separate stowed file and are imported here:

@CLAUDE.company.md

## Preferences
```

- [ ] **Step 3: Verify both files are valid and the import line is present**

Run: `grep -n '@CLAUDE.company.md' claude/.claude/CLAUDE.md && head -1 claude/.claude/CLAUDE.company.md`
Expected: the grep prints the `@CLAUDE.company.md` line; head prints `# Company configuration`.

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/CLAUDE.company.md claude/.claude/CLAUDE.md
git commit -m "feat(claude): add company wiki consultation instructions"
```

---

## Task 3: Document the qmd-wiki posture in the project CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (repo root) — two edits

- [ ] **Step 1: Document the instructions-layering / import mechanism**

In the repo-root `CLAUDE.md`, in the "Claude Code settings (layered merge)" section, replace:

```markdown
copies the base as-is.

## Permission posture
```

with:

```markdown
copies the base as-is.

Instructions layer separately from settings: `claude/.claude/CLAUDE.md` holds
personal defaults and imports company-wide instructions via
`@CLAUDE.company.md` (a native Claude Code import, resolved relative to the
stowed `~/.claude/CLAUDE.md`). `claude-sync` does not touch CLAUDE.md -- the
import is resolved by Claude Code at load time.

## Permission posture
```

- [ ] **Step 2: Document the qmd-wiki overlay permission posture**

In the same file, in the "Permission posture" section, replace:

```markdown
  by exact name in `ask` (ask beats allow). Verified by
  `claude/.claude/tests/mcp-permission-overlay/run.sh`.

Per-repo overrides live in `.claude/settings.local.json` (gitignored).
```

with:

```markdown
  by exact name in `ask` (ask beats allow). Verified by
  `claude/.claude/tests/mcp-permission-overlay/run.sh`.
- qmd company-wiki posture (company overlay): the four read tools
  (`mcp__qmd__query`, `mcp__qmd__get`, `mcp__qmd__multi_get`,
  `mcp__qmd__status`) are auto-allowed by exact name so wiki queries skip the
  classifier. qmd indexing/write tools are intentionally not allowed --
  indexing stays a manual user action. The "when to query the wiki" directive
  lives in `claude/.claude/CLAUDE.company.md` (imported into the personal
  `CLAUDE.md`), not in settings. Verified by the same
  `mcp-permission-overlay` test.

Per-repo overrides live in `.claude/settings.local.json` (gitignored).
```

- [ ] **Step 3: Verify both edits landed**

Run: `grep -n 'qmd company-wiki posture\|Instructions layer separately' CLAUDE.md`
Expected: two matching lines printed.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): document qmd wiki overlay posture and company import"
```

---

## Task 4: Verification

**Files:** none modified — this task only verifies.

- [ ] **Step 1: Validate JSON of base + overlay**

Run: `jq empty claude/.claude/settings.base.json && jq empty claude/.claude/settings.overlay.json && echo OK`
Expected: `OK`.

- [ ] **Step 2: Run the overlay permission test (the real in-worktree gate)**

Run: `bash claude/.claude/tests/mcp-permission-overlay/run.sh`
Expected: `mcp-permission-overlay: all passed`, exit 0. (The test reads the worktree's base/overlay directly, so it validates this branch's edits without stowing.)

- [ ] **Step 3: Confirm the merged allow list contains the qmd tools (mirrors claude-sync merge)**

Run:
```bash
jq -n --slurpfile b claude/.claude/settings.base.json --slurpfile o claude/.claude/settings.overlay.json '
  def merge(x): if (type=="array") and (x|type=="array") then
      (if all(type=="string") and (x|all(type=="string"))
       then reduce (.+x)[] as $i ([]; if index($i) then . else .+[$i] end) else .+x end)
    elif (type=="object") and (x|type=="object") then
      reduce (x|to_entries[]) as $e (.; if has($e.key) then .[$e.key]|=merge($e.value) else .+{($e.key):$e.value} end)
    else x end;
  ($b[0]|merge($o[0])).permissions.allow | map(select(startswith("mcp__qmd__")))'
```
Expected: a JSON array with `mcp__qmd__query`, `mcp__qmd__get`, `mcp__qmd__multi_get`, `mcp__qmd__status`.

- [ ] **Step 4: Record post-merge manual steps (no action in-worktree)**

These require the branch merged to `main` and re-stowed (the live `~/.claude/CLAUDE.md` symlink and `claude-sync` read from the main checkout, not this worktree):

1. `claude-sync` — regenerate `~/.claude/settings.json`; confirm its `allow` contains the four qmd tools.
2. `mkdir -p ~/.local/bin` not needed here; `stow -t ~ -R claude` — ensure `~/.claude/CLAUDE.company.md` symlink exists.
3. Fresh session sanity: a company-flavored prompt triggers an `mcp__qmd__query` against collection `wiki` with no permission prompt.

No commit (verification only).

---

## Self-review

- **Spec coverage:** overlay qmd allows (Task 1), CLAUDE.company.md (Task 2 Step 1), `@import` line (Task 2 Step 2), test extension (Task 1), project-CLAUDE.md docs (Task 3), verification (Task 4). All five spec components + verification covered.
- **Placeholder scan:** none — every code/config step shows exact final content and exact old/new anchors.
- **Type/name consistency:** tool names `mcp__qmd__{query,get,multi_get,status}` and collection name `wiki` are identical across the overlay, the test, the instructions file, and the docs.
