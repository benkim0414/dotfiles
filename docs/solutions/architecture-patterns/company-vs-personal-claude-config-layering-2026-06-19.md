---
title: "Layer company Claude config separately from personal: permissions in settings overlay, instructions via CLAUDE.md @import"
date: 2026-06-19
category: architecture-patterns
module: claude-code-config
problem_type: architecture_pattern
component: tooling
severity: medium
applies_when:
  - "Adding company-wide Claude config that must stay distinct from personal defaults"
  - "A capability needs BOTH a permission grant and a behavioral 'when to do X' directive"
  - "Enabling an MCP tool (e.g. qmd wiki) for company use across all sessions"
tags: [claude-config, settings-overlay, claude-md-import, claude-sync, mcp, qmd, layering]
---

# Layer company Claude config separately from personal: permissions in settings overlay, instructions via CLAUDE.md @import

## Context

The request was to make Claude consult the company knowledge base (the qmd
`wiki` collection indexed from `~/workspace/wiki`) during sessions, with the
config set up in the repo's **company overlay** to keep it distinct from
personal defaults.

The friction: `settings.overlay.json` is the company layer, but it is a Claude
Code **settings** file (permissions / hooks / env). It cannot carry behavioral
instructions like "query the wiki when starting a task." Those live in
CLAUDE.md. So "put it in the overlay" does not have a single home — a
capability that needs both a permission and a directive splits across two
layers, and the repo had no company-vs-personal split for CLAUDE.md.

## Guidance

Split company config **by artifact type**, not by capability:

1. **Permissions / settings → `claude/.claude/settings.overlay.json`** (the
   company overlay). `claude-sync` merges base + overlay into the generated
   `~/.claude/settings.json`. Grant MCP tools by **exact name** (no
   `mcp__server__*` wildcard in `allow` — allow requires a literal, glob-free
   server segment), and grant only the read tools so write/index tools fall to
   the auto-mode classifier.

2. **Behavioral instructions → a separate `claude/.claude/CLAUDE.company.md`**,
   pulled into the personal `claude/.claude/CLAUDE.md` with a single native
   import line `@CLAUDE.company.md`. The personal file's only company coupling
   is that one line; all company substance lives in the imported file.
   `claude-sync` does **not** touch CLAUDE.md — Claude Code resolves the import
   at load time, relative to the importing file's directory (both files stow to
   `~/.claude/`, so `~/.claude/CLAUDE.md` → `~/.claude/CLAUDE.company.md`).

3. **Verify the permission half with the existing overlay test.** Extend
   `claude/.claude/tests/mcp-permission-overlay/run.sh` with positive cases
   (each granted tool → `allow`) and a negative case (an unlisted tool from the
   same server → `classifier`) so a future blanket wildcard can't silently
   widen the grant.

## Why This Matters

- A settings file silently ignores prose; a CLAUDE.md import silently ignores
  permission grants. Putting each in the wrong home produces config that looks
  present but does nothing. Splitting by artifact type is the only arrangement
  where both halves actually take effect.
- The exact-name allow-list is what enforces "indexing stays a manual user
  action." A `mcp__qmd__*` wildcard would have silently admitted
  `collection add` / `embed` / `update`. The negative test case is the guard.
- Keeping the directive in `CLAUDE.company.md` means its trigger framing (e.g.
  "at the START of any non-trivial task") can be tuned later without touching
  personal defaults — the isolation the request asked for.

## When to Apply

- Any company-wide Claude config that should not bleed into personal defaults.
- Any capability that needs a permission grant **and** a behavioral directive —
  the two land in different layers by necessity, not preference.
- Enabling an MCP server's read tools fleet-wide while leaving its mutating
  tools ungranted.

## Examples

Overlay permission grant (exact-name, read-only — `settings.overlay.json`):

```json
"allow": [
  "mcp__atlassian__*",
  "mcp__slack__*",
  "mcp__qmd__query",
  "mcp__qmd__get",
  "mcp__qmd__multi_get",
  "mcp__qmd__status"
]
```

Personal-to-company link (one line in `claude/.claude/CLAUDE.md`):

```markdown
## Company configuration

Company-wide instructions (distinct from these personal defaults) live in a
separate stowed file and are imported here:

@CLAUDE.company.md
```

Overlay test guard (`mcp-permission-overlay/run.sh`):

```bash
expect mcp__qmd__query                             allow
expect mcp__qmd__get                               allow
expect mcp__qmd__multi_get                         allow
expect mcp__qmd__status                            allow
# only the four named read tools are allow-listed; anything else qmd
# exposes falls to the auto-mode classifier (no blanket qmd allow)
expect mcp__qmd__some_other_tool                   classifier
```

Trigger note: the directive is instruction-only (no hook). A per-prompt
auto-query hook was considered and rejected — it taxes every turn (qmd call +
injected tokens + latency) including trivial prompts. The always-loaded
directive queries at task start where the value is.

Post-merge gotcha: the permission half is verifiable in-worktree (the test
reads the repo files directly), but the `@import` half only resolves after the
branch is merged to main and re-stowed (`claude-sync` then `stow -t ~ -R
claude`) — the live `~/.claude/CLAUDE.md` symlink points at the main checkout,
not the worktree.

## Related

- docs/solutions/tooling-decisions/claude-code-permission-deny-ask-allow-precedence-2026-06-18.md
  -- the precedence + overlay-merge mechanics this builds on (deny->ask->allow,
  concat-only merge, allow needs a glob-free server segment). This doc reuses
  that plumbing for qmd read-tool auto-allow and adds the CLAUDE.md @import layer.
- docs/solutions/conventions/mcp-ask-overrides-destructive-tools-2026-05-25.md
  -- exact-name allow/ask convention for MCP tools; basis for auto-allowing qmd
  query/get/multi_get/status by name while leaving indexing ungranted.
- docs/solutions/workflow-issues/encode-workflow-preferences-via-claude-md-2026-05-26.md
  -- "directives that can't be a settings.json rule belong in CLAUDE.md"; this
  doc applies that to the company/personal split via @CLAUDE.company.md.
- docs/solutions/developer-experience/claude-settings-permission-rule-warnings-2026-06-12.md
  -- why allow rules need a literal, glob-free server segment (no bare mcp__* in allow).
- docs/solutions/claude-permissions-hardening.md
  -- foundational defaultMode:auto + classifier + claude-sync re-sync pitfall.
