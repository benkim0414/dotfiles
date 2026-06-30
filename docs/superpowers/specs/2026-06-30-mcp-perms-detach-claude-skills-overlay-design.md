# Detach the stale claude-skills settings overlay

Date: 2026-06-30

## Problem

Claude Code prompts for confirmation on non-destructive Jira/Atlassian
operations (e.g. `createJiraIssue`, `jira_create_issue`) despite the company
overlay auto-allowing `mcp__atlassian__*`. The prompt cites the rule
`mcp__*__*create*`.

## Root cause

Two independent facts combine:

1. **`ask` beats `allow` unconditionally.** Per the official permissions docs:
   "Rules are evaluated in order: deny, then ask, then allow... rule
   specificity doesn't change the order... a matching ask rule prompts even
   when a more specific allow rule also matches the same call." So an `allow`
   rule — even an exact-name one — can never suppress a matching `ask` glob.

2. **`claude-sync`'s overlay merge only concatenates arrays; it cannot
   subtract.** The generated `~/.claude/settings.json` is
   `settings.base.json` folded with the dotfiles company overlay and the
   claude-skills overlay, in that order, with string arrays
   concatenated + deduplicated.

The dotfiles `settings.base.json` `ask` list deliberately gates only
genuinely destructive MCP verbs: `delete, remove, sync, deploy, apply, patch,
write`. It intentionally does **not** gate `create/update/edit/add/transition`
(documented in `CLAUDE.md`).

`~/workspace/claude-skills/settings.overlay.json` is a **stale duplicate of
the old, broader policy**. Its `ask` list re-adds
`mcp__*__*create*`, `*update*`, `*edit*`, `*add*`, `*transition*`, `*invoke*`.
The merge concatenates these into the global `ask` list, and because `ask`
beats `allow`, the company overlay's `mcp__atlassian__*` allow is powerless to
suppress them. Result: every Atlassian create/update/transition/add call
prompts.

Because the merge cannot subtract, **dotfiles cannot remove these globs by
editing its own files** — the fix must address the claude-skills overlay's
participation in the merge.

## Decision

Detach the claude-skills overlay from `claude-sync` entirely. The
claude-skills overlay is stale (its broad verb gating predates the base's
move to destructive-only gating). Making `settings.base.json` + the dotfiles
company overlay the sole authority for MCP verb gating removes the drift at
its structural source.

Destructive set stays at `delete` + `remove` for the user-facing intent
("allow all except destructive"), while the base's infra-protecting verbs
(`sync/deploy/apply/patch/write`) remain gated — they do not match any
Atlassian tool, so they cost nothing for the Atlassian goal and continue to
guard infra MCP servers.

## Changes (all in the dotfiles repo)

1. **`bin/.local/bin/claude-sync`** — drop claude-skills overlay discovery:
   - Remove the `SKILLS="${CLAUDE_SKILLS_DIR:-$HOME/workspace/claude-skills}"`
     variable.
   - Remove the `SKILLS_OVERLAY="$SKILLS/settings.overlay.json"` variable.
   - Remove the `[[ -f "$SKILLS_OVERLAY" ]] && overlays+=("$SKILLS_OVERLAY")`
     append.
   - Update the header comment block so it describes a single (dotfiles
     company) overlay.

   The merge logic itself is unchanged: it already reduces over an overlay
   array, now of length 1.

2. **`CLAUDE.md`** — rewrite the "Claude Code settings (layered merge)"
   section. It currently documents two overlays folded in order. Drop overlay
   #2 (claude-skills) and add a one-line note that it was detached on
   2026-06-30 because its `ask` globs re-gated Atlassian non-destructive
   tools (`ask` beats `allow`; the concatenating merge cannot subtract).

3. **Regenerate + verify** — run `claude-sync`, then assert against the
   generated `~/.claude/settings.json`:
   - `permissions.ask` contains none of
     `mcp__*__*create*`, `*update*`, `*edit*`, `*add*`, `*transition*`,
     `*invoke*`.
   - `permissions.allow` still contains `mcp__atlassian__*`.
   - `permissions.ask` still contains the base destructive set
     (`mcp__*__*delete*`, `*remove*`, `*sync*`, `*deploy*`, `*apply*`,
     `*patch*`, `*write*`) and the five exact-name Atlassian destructive
     re-gates.

## Resulting behavior (any repo)

| Tool call | Matching rule | Outcome |
|---|---|---|
| `jira_create_issue` / `createJiraIssue` | `mcp__atlassian__*` (allow); no ask match | allowed silently |
| `jira_update_issue` / `transitionJiraIssue` | `mcp__atlassian__*` (allow); no ask match | allowed silently |
| `jira_delete_issue` / `deleteJiraIssue` | `mcp__*__*delete*` (ask) + exact ask | confirm |
| `jira_remove_issue_link` | `mcp__*__*remove*` (ask) + exact ask | confirm |
| infra `*apply*` / `*sync*` | base `mcp__*__*apply*` / `*sync*` (ask) | confirm |

## Consequences

- **Session restart required.** Permission rules load at session start. Any
  running session (e.g. the `ops` repo session that surfaced the prompt) must
  be restarted to pick up the regenerated global settings.
- **claude-skills hooks dropped from global settings.** The overlay also
  declared two hooks (a kubernetes `production-guard` PreToolUse and a
  `validate-skill-frontmatter` PostToolUse). Both used **relative** command
  paths (`bash sre/hooks/...`), so they only ever resolved when cwd was the
  claude-skills repo. Detaching drops them from the global settings.
  Accepted: claude-skills is treated as stale. No preservation work is part of
  this change.
- **Redundant ops-local allow.** The `ops` repo's
  `.claude/settings.local.json` lists `mcp__atlassian__createJiraIssue` in
  `allow`; it becomes redundant (the company allow covers it) but is harmless.

## Out of scope

- Editing the claude-skills repo (adding a project-scope `.claude/settings.json`
  to retain its hooks). Separate repo, separate workflow.
- Any change to the base destructive verb set.
