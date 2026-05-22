# Permissions: auto mode default + blanket MCP allow

**Status:** approved (design)
**Date:** 2026-05-22
**Branch:** worktree-permissions-auto-default

## Goal

Two behavior changes in the user-scope Claude Code settings:

1. `defaultMode` flips from `acceptEdits` to `auto`. New sessions open in auto
   mode (classifier judges unmatched tool calls; no per-tool prompts for
   allowed tools).
2. `permissions.allow` adds a blanket `mcp__*` rule. All MCP server tools
   (`mcp__plugin_context-mode_context-mode__*`, `mcp__atlassian__*`,
   `mcp__slack__*`, `mcp__qmd__*`, `mcp__sequential-thinking__*`,
   `mcp__claude_ai_*__*`, future servers) skip the prompt path entirely.

Redundant specific MCP allow entries (`mcp__sequential-thinking__*`,
`mcp__qmd__*`) are removed since the wildcard supersedes them.

## Motivation

Current session friction:

- Context-mode MCP tools (`ctx_fetch_and_index`, `ctx_execute`, `ctx_search`)
  fall through the allow list and hit the classifier. External URL fetches
  trigger prompts because target domains are not in `autoMode.environment`.
- Atlassian, Slack, Linear, Notion MCP tools all behave the same — every
  call is classified individually, often interrupting flow.
- `acceptEdits` mode does not eliminate these prompts (it only auto-accepts
  file edits).

User accepts the broad blast radius of `mcp__*` allow and will restrict
sensitive operations per-repo via `.claude/settings.local.json` `ask` and
`deny` rules where needed.

## Non-goals

- Customizing the `autoMode` classifier (`environment`, `allow`, `soft_deny`,
  `hard_deny`). Defaults are sufficient for non-MCP tools.
- Touching project-level `.claude/settings.local.json` files. Per-repo deny
  list maintenance is the user's manual call.
- Changing hook code in `claude/.claude/hooks/`. None of the safety hooks
  (`git-safety.sh`, `worktree-exited.sh`, `restore-git-context.sh`,
  `git-session-start.sh`) read `defaultMode` or MCP permissions. They
  continue to enforce worktree isolation + main-branch protection
  regardless of mode.
- Touching the `claude-skills` overlay file (`settings.overlay.json`). This
  change is in the base; the overlay merges on top via `claude-sync`.

## Decisions

### D1: `defaultMode` value = `"auto"`

Per Claude Code docs: `auto` is honored only when set in `~/.claude/settings.json`
(user scope). Project/local `.claude/settings.json`/`.claude/settings.local.json`
ignore it (security: untrusted repo can't grant itself auto mode).

`claude-sync` generates `~/.claude/settings.json` from
`claude/.claude/settings.base.json` + optional
`~/workspace/claude-skills/settings.overlay.json`. The generated file lives
at user scope, so `auto` will take effect.

Requires Claude Code v2.1.83+ (auto mode) and Sonnet 4.6 / Opus 4.6 / Opus 4.7.
User runs Opus 4.7 per base settings (`"model": "opus[1m]"`) — supported.

### D2: Wildcard `mcp__*` instead of per-server entries

`permissions.allow` runs BEFORE the classifier. Matching the wildcard
short-circuits the classifier per MCP call.

Trade-off: future-added MCP servers (e.g., new claude.ai integrations)
are auto-trusted with no settings edit. User accepts. Per-repo
`.claude/settings.local.json` is the choke point if a specific server
needs tightening.

Drops:
- `"mcp__sequential-thinking__*"` (covered by wildcard)
- `"mcp__qmd__*"` (covered by wildcard)

### D3: `autoMode` config not touched

Default `soft_deny`/`hard_deny` rules ship with the classifier and adapt
across releases. No custom rules needed yet. Revisit if classifier
repeatedly flags a routine pattern.

### D4: Documentation updates in `CLAUDE.md`

Add a short subsection under the Claude Code settings section explaining:
- User scope = auto mode + blanket MCP allow (rationale: research preview;
  classifier nudges no-question workflow).
- Per-repo overrides go in `.claude/settings.local.json` (not committed)
  via `permissions.ask` / `permissions.deny`.

## Edits

### E1: `claude/.claude/settings.base.json` — flip `defaultMode`

```diff
-  "defaultMode": "acceptEdits",
+  "defaultMode": "auto",
```

### E2: `claude/.claude/settings.base.json` — replace specific MCP allow entries with wildcard

```diff
       "CronList",
-      "mcp__sequential-thinking__*",
-      "mcp__qmd__*"
+      "mcp__*"
     ],
```

### E3: `CLAUDE.md` (dotfiles project root) — document the permission posture

Insert a new subsection between the existing `# Claude Code settings
(dual-repo merge)` body and the `# Brewfile rules` heading. Inserted text
(verbatim — note: this is the literal markdown to add, fenced here in the
spec for clarity):

````markdown
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
````

Heading level is `##` because it lives under the existing `# Claude Code
settings (dual-repo merge)` top-level section. Insertion lands directly
before the `# Brewfile rules` line.

## Verification

After applying edits and running `claude-sync`:

```bash
jq '.defaultMode, .permissions.allow' ~/.claude/settings.json
```

Expected output:
- `.defaultMode` == `"auto"`
- `.permissions.allow` includes `"mcp__*"` and does NOT include
  `"mcp__sequential-thinking__*"` or `"mcp__qmd__*"` (unless overlay
  re-adds them, which it should not).

Smoke test: restart Claude Code in a non-no-pr repo. Confirm new session
header shows auto mode. Run any context-mode MCP call (`ctx_search`)
in a fresh project — should execute without prompt.

## Risks + mitigations

- **R1: Classifier blocks routine commands user wants.** The session-history
  learning (`docs/solutions/workflow-issues/classifier-conflates-session-topic-with-action-intent-2026-05-22.md`)
  documents a false-positive on `git worktree remove` + `git branch -d`
  chained with `&&`. Mitigation: split into separate Bash calls, or add
  the pattern to project `.claude/settings.local.json` allow.
- **R2: Blanket `mcp__*` allow exposes destructive MCP ops.** E.g.,
  `mcp__claude_ai_Linear__*` could include issue deletion via future
  tools. Mitigation: per-repo `ask`/`deny` rules. User explicit accepted.
- **R3: Overlay (`claude-skills`) re-adds specific MCP entries.** `claude-sync`
  concatenates + dedupes arrays. Re-added specific entries are no-ops
  alongside the wildcard. Safe.
- **R4: `mcp__*` matches `mcp__claude_ai_*__authenticate` (OAuth flow).**
  Auth flows still print a URL the user must click; no prompt skip needed
  since the user interaction happens in the browser, not the tool call.
  Safe.

## Out of scope

- Project-level `.claude/settings.local.json` template for sensitive repos.
- Migration of any existing per-repo settings.
- Changes to the `claude-skills` overlay.
- `autoMode` custom rules.
