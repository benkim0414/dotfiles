# Auto-allow atlassian + slack MCP except destructive

**Date:** 2026-06-18
**Status:** Approved
**Scope:** dotfiles `claude/` package — permission policy + claude-sync merge

## Problem

Under `defaultMode: auto`, atlassian and slack MCP read tools pass the
classifier silently, but every write is force-prompted by the
server-agnostic mutation globs in `settings.base.json`'s `ask` list
(`mcp__*__*create*`, `*update*`, `*edit*`, `*add*`, `*transition*`, etc.).
The user wants every atlassian/slack operation auto-allowed **except
destructive ones** (irreversible delete/remove), in a separate
company-only settings file rather than baked into the shared base.

## Key constraint

Claude Code evaluates permission rules **deny → ask → allow**; the first
match wins and specificity does not change the order. A matching `ask`
rule prompts **even when a more specific `allow` rule also matches**
(source: docs.claude.com/en/docs/claude-code/permissions). The
`claude-sync` overlay merge only **concatenates + deduplicates** string
arrays — it can add entries but cannot remove base entries.

Consequence: an overlay `allow` entry alone cannot free a write that
already matches a base `ask` glob. The base globs that catch
atlassian/slack writes **must be narrowed in base**. Overlay-only solves
reads, not writes.

## Tool classification

**Bucket A — read-only (auto-allow):** all `jira_get_*`, `jira_search`,
`jira_search_fields`, `jira_batch_get_changelogs`,
`jira_download_attachments`; all `confluence_get_*`, `confluence_search`,
`confluence_search_user`, `confluence_download_*`;
`slack_get_channel_history`, `slack_get_thread_replies`,
`slack_get_user_profile`, `slack_get_users`, `slack_list_channels`.

**Bucket B — non-destructive writes (auto-allow):** jira `add_comment`,
`add_worklog`, `add_watcher`, `add_issues_to_sprint`, `create_issue`,
`batch_create_issues`, `create_version`, `batch_create_versions`,
`create_sprint`, `create_issue_link`, `create_remote_issue_link`,
`edit_comment`, `update_issue`, `update_sprint`,
`update_proforma_form_answers`, `transition_issue`, `link_to_epic`;
confluence `add_comment`, `add_label`, `reply_to_comment`, `create_page`,
`update_page`, `move_page`, `upload_attachment`, `upload_attachments`;
slack `add_reaction`, `post_message`, `reply_to_thread`.

**Bucket C — destructive (keep gated / ask):** jira `delete_issue`,
`remove_issue_link`, `remove_watcher`; confluence `delete_page`,
`delete_attachment`. (Slack MCP has no delete.)

Decision: auto-allow A + B, gate only C.

## Design

### Component 1 — narrow base global mutation gate

In `claude/.claude/settings.base.json` `permissions.ask`, remove the
non-destructive write verb globs and keep the destructive + high-impact
ones:

- **Remove:** `mcp__*__*create*`, `mcp__*__*update*`, `mcp__*__*edit*`,
  `mcp__*__*add*`, `mcp__*__*transition*`
- **Keep:** `mcp__*__*delete*`, `mcp__*__*remove*` (destructive), plus
  `mcp__*__*sync*`, `mcp__*__*deploy*`, `mcp__*__*apply*`,
  `mcp__*__*patch*`, `mcp__*__*write*` (high-impact; no atlassian/slack
  tool contains these verbs, so keeping them preserves caution for future
  servers without blocking the goal).
- **Unchanged:** named `ctx_purge` / `ctx_upgrade` ask entries.

Effect for non-atlassian/slack servers: their `create`/`update`/`edit`/
`add`/`transition` tools fall to the auto-mode classifier instead of
force-ask. In practice no current server (qmd, sequential-thinking,
context-mode) has such tools, so there is no behavioral regression today.

### Component 2 — company overlay file

New file `claude/.claude/settings.overlay.json`, committed to dotfiles:

```json
{
  "permissions": {
    "allow": ["mcp__atlassian__*", "mcp__slack__*"],
    "ask": [
      "mcp__atlassian__jira_delete_issue",
      "mcp__atlassian__jira_remove_issue_link",
      "mcp__atlassian__jira_remove_watcher",
      "mcp__atlassian__confluence_delete_page",
      "mcp__atlassian__confluence_delete_attachment"
    ]
  }
}
```

- `allow` uses tool-position wildcards after a literal, glob-free server
  segment (`mcp__atlassian__*`, `mcp__slack__*`) — valid in `allow`.
- The 5 `ask` exact names are belt-and-suspenders: base `*delete*` /
  `*remove*` already catch them, but the explicit list documents the
  company destructive set and survives future base edits.
- Bucket C tools appear **only** in `ask`, never in `allow` (ask > allow
  must resolve to a prompt).

Resolution after merge (representative):
- `jira_create_issue` → no deny, no ask match, `mcp__atlassian__*` allow → **allow**
- `slack_post_message` → no ask match, `mcp__slack__*` allow → **allow**
- `jira_delete_issue` → base `*delete*` + overlay exact ask → **ask**
- `confluence_delete_attachment` → base `*delete*` + overlay exact ask → **ask**
- `jira_remove_watcher` → base `*remove*` + overlay exact ask → **ask**

### Component 3 — claude-sync layering

`bin/.local/bin/claude-sync` currently merges `base + claude-skills
overlay → settings.json`. Change to fold-merge in order:

```
base
  + $DOTFILES/claude/.claude/settings.overlay.json   (always, if present)
  + $CLAUDE_SKILLS_DIR/settings.overlay.json          (if present)
  → ~/.claude/settings.json
```

Same merge semantics (string arrays concat+dedup, object arrays concat,
objects deep-merge overlay-wins, scalars overlay-wins). Apply the
existing `merge(b)` jq function iteratively over the ordered list of
present overlay files. When no overlay is present, copy base as-is
(unchanged fallback). claude-skills overlay still works when un-stale;
later overlays win on scalar conflicts.

Note: the new overlay lives in the `claude/` stow package, so `stow -R
claude` symlinks it to `~/.claude/settings.overlay.json`. Harmless —
Claude Code reads only the generated `settings.json`; claude-sync reads
the overlay from the `$DOTFILES` path.

### Component 4 — docs

Update dotfiles `CLAUDE.md`:
- "Claude Code settings (dual-repo merge)" — document the layered overlay
  order and the new `claude/.claude/settings.overlay.json` input.
- "Permission posture" — record the narrowed global gate (destructive +
  high-impact verbs only) and the atlassian/slack auto-allow-except-
  destructive policy.

## Verification

- `jq empty` parses `settings.base.json` and `settings.overlay.json`.
- Merged output (`base + overlay` via the claude-sync jq) is valid JSON
  and contains the expected `allow`/`ask` entries with no duplicates.
- Precedence assertions over representative tools: Bucket A/B samples
  (`jira_create_issue`, `slack_post_message`, `confluence_update_page`,
  `jira_get_issue`) resolve to allow-not-ask; Bucket C
  (`jira_delete_issue`, `confluence_delete_attachment`,
  `jira_remove_watcher`) resolve to ask.
- Implemented as a committed test under `claude/.claude/tests/` following
  the existing `commit-scope` / `permission-policy` convention
  (`run.sh`, exit non-zero on failure).

## Out of scope

- The `claude_ai_*` connector servers (separate branch concern).
- Any change to qmd / sequential-thinking / context-mode gating.
- Secrets — the overlay contains only generic MCP tool-name rules, safe
  to commit to dotfiles.
