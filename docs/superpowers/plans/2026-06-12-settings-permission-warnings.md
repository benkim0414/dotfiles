# Settings Permission Warnings Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the removed-tool `MultiEdit` references and the invalid `mcp__*` allow rule from `settings.base.json` so `claude` launches with zero permission warnings.

**Architecture:** All permission rules live in `claude/.claude/settings.base.json`, which `claude-sync` deep-merges into the generated `~/.claude/settings.json`. Edit the base file only. `MultiEdit` was folded into `Edit` (its paired `Edit(...)` deny rules already cover the same paths), so removing `MultiEdit` loses no protection. Bare `mcp__*` is invalid in `allow`; dropping it routes MCP calls through the `defaultMode: auto` classifier while existing `ask` rules still gate mutations.

**Tech Stack:** JSON config, `claude-sync` (bash), GNU Stow.

---

### Task 1: Remove `MultiEdit` and `mcp__*` from `permissions.allow`

**Files:**
- Modify: `claude/.claude/settings.base.json` (allow array, lines ~19 and ~39)

- [ ] **Step 1: Remove the `MultiEdit` allow entry**

Delete this line from the `allow` array (it sits between `"Edit",` and `"NotebookEdit",`):

```json
      "MultiEdit",
```

- [ ] **Step 2: Remove the `mcp__*` allow entry**

The `mcp__*` entry is the last item in the `allow` array, preceded by `"CronList",`. Remove the `mcp__*` line and the trailing comma on `CronList` so the array stays valid JSON:

Before:
```json
      "CronList",
      "mcp__*"
    ],
```

After:
```json
      "CronList"
    ],
```

- [ ] **Step 3: Verify JSON still parses**

Run: `python3 -m json.tool claude/.claude/settings.base.json > /dev/null && echo OK`
Expected: `OK`

---

### Task 2: Remove `MultiEdit(...)` rules from `permissions.deny`

**Files:**
- Modify: `claude/.claude/settings.base.json` (deny array, lines ~48-81)

- [ ] **Step 1: Delete all 11 `MultiEdit(...)` deny lines**

Remove each of these lines from the `deny` array. Each has a paired `Edit(...)` line immediately above it that stays:

```json
      "MultiEdit(**/.env)",
      "MultiEdit(**/.env.*)",
      "MultiEdit(~/.ssh/*)",
      "MultiEdit(~/.gnupg/*)",
      "MultiEdit(~/.aws/credentials)",
      "MultiEdit(~/.claude/.credentials.json)",
      "MultiEdit(~/.kube/config)",
      "MultiEdit(~/.docker/config.json)",
      "MultiEdit(~/.netrc)",
      "MultiEdit(~/.config/gh/hosts.yml)",
```

Note: that is 10 distinct paths; `**/.env` and `**/.env.*` are two separate lines, totaling 11 `MultiEdit` deny entries removed. After deletion, confirm zero `MultiEdit` deny rules remain.

- [ ] **Step 2: Verify no `MultiEdit` remains in deny and JSON parses**

Run: `grep -c 'MultiEdit(' claude/.claude/settings.base.json; python3 -m json.tool claude/.claude/settings.base.json > /dev/null && echo OK`
Expected: first line `0`, then `OK`

---

### Task 3: Remove `MultiEdit` token from hook matchers

**Files:**
- Modify: `claude/.claude/settings.base.json` (PreToolUse + PostToolUse matchers, lines ~248, ~257, ~296)

- [ ] **Step 1: Fix the worktree-guard matcher**

Replace:
```json
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
```
With:
```json
        "matcher": "Write|Edit|NotebookEdit",
```

- [ ] **Step 2: Fix the permission-policy matcher**

Replace:
```json
        "matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit|WebFetch",
```
With:
```json
        "matcher": "Bash|Write|Edit|NotebookEdit|WebFetch",
```

- [ ] **Step 3: Fix the audit-log matcher**

Replace:
```json
        "matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit|CronCreate|CronDelete|RemoteTrigger|Read|NotebookRead|Grep|mcp__qmd__get|mcp__qmd__multi_get",
```
With:
```json
        "matcher": "Bash|Write|Edit|NotebookEdit|CronCreate|CronDelete|RemoteTrigger|Read|NotebookRead|Grep|mcp__qmd__get|mcp__qmd__multi_get",
```

- [ ] **Step 4: Verify zero `MultiEdit` remains anywhere and JSON parses**

Run: `grep -c 'MultiEdit' claude/.claude/settings.base.json; python3 -m json.tool claude/.claude/settings.base.json > /dev/null && echo OK`
Expected: first line `0`, then `OK`

- [ ] **Step 5: Commit the settings change**

```bash
git add claude/.claude/settings.base.json
git commit -m "fix(permissions): drop removed MultiEdit tool and invalid mcp__* allow

MultiEdit was folded into Edit; its deny rules and matcher tokens
referenced a non-existent tool and triggered launch warnings. Paired
Edit(...) deny rules already cover the same secret paths.

Bare mcp__* is invalid in allow rules (only deny/ask accept bare
wildcards). Dropped it; auto-mode classifier judges MCP calls and the
existing ask mutation rules still gate writes.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Update `CLAUDE.md` "Permission posture" doc

**Files:**
- Modify: `CLAUDE.md` ("Permission posture" section)

- [ ] **Step 1: Locate the current allow bullet**

Find this bullet under "User-scope defaults":

```markdown
- `permissions.allow: ["mcp__*", ...]` -- all MCP server tools skip the
  prompt path. Includes context-mode, qmd, sequential-thinking,
  Atlassian, Slack, Linear, Notion, claude.ai integrations, future
  servers.
- Two destructive context-mode tools are walked back into `ask` so
  they prompt despite the broad `mcp__*` allow:
  `mcp__plugin_context-mode_context-mode__ctx_purge` (wipes the FTS5
  knowledge base, irreversible) and
  `mcp__plugin_context-mode_context-mode__ctx_upgrade` (pulls, builds,
  and installs from GitHub). `ask` overrides `allow` per Claude Code
  precedence.
```

- [ ] **Step 2: Replace with the new posture**

```markdown
- MCP tools are not pre-approved in `allow` (bare `mcp__*` is invalid
  there -- only `deny`/`ask` accept bare wildcards). Under
  `defaultMode: "auto"` the classifier judges each unmatched MCP call.
- `ask` rules still gate MCP mutations: the `mcp__*__*create*`,
  `*delete*`, `*update*`, `*write*` (etc.) globs, plus two destructive
  context-mode tools --
  `mcp__plugin_context-mode_context-mode__ctx_purge` (wipes the FTS5
  knowledge base, irreversible) and
  `mcp__plugin_context-mode_context-mode__ctx_upgrade` (pulls, builds,
  and installs from GitHub).
```

- [ ] **Step 3: Verify the stale claim is gone**

Run: `grep -n 'mcp__\*", ...\|skip the prompt path\|overrides .allow. per' CLAUDE.md || echo CLEAN`
Expected: `CLEAN`

- [ ] **Step 4: Commit the doc change**

```bash
git add CLAUDE.md
git commit -m "docs(permissions): describe auto-mode MCP posture

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Regenerate and verify

**Files:**
- Generated (not committed): `~/.claude/settings.json`

- [ ] **Step 1: Regenerate settings.json**

Run: `claude-sync`
Expected: completes without error.

- [ ] **Step 2: Confirm the generated file is clean**

Run:
```bash
grep -c 'MultiEdit' ~/.claude/settings.json
python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/.claude/settings.json'))); print('mcp__* in allow:', 'mcp__*' in d['permissions']['allow'])"
```
Expected: first line `0`; second line `mcp__* in allow: False`.

- [ ] **Step 3: Confirm no launch warnings**

Open a new `claude` session (or reload settings). Confirm:
- No `"MultiEdit(...)" matches no known tool` warnings.
- No `Invalid permission rule "mcp__*" was skipped` warning.

If warnings persist, re-check that `claude-sync` read the edited base file and that no work overlay reintroduces `mcp__*` or `MultiEdit`.
