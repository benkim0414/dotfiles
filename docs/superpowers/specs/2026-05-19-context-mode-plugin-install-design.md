# context-mode plugin install + remember cleanup -- design

**Date:** 2026-05-19
**Branch:** `worktree-context-mode-install`
**Scope:** two independent `enabledPlugins` edits to `claude/.claude/settings.base.json`, sharing one worktree.

## Goals

1. **Cleanup.** Remove the disabled `"remember@claude-plugins-official": false` entry from `enabledPlugins`. The line was retained from a prior config to suppress the plugin; the suppression is no longer needed and the line is dead config.
2. **Install.** Adopt the `context-mode` plugin (`mksglu/context-mode`) by enabling it in `enabledPlugins` after running the marketplace + plugin install slash commands in the REPL.

The two goals are independent. They land as two atomic commits in one worktree to share a single `claude-sync` verify + merge cycle, not because they are coupled.

## Non-goals

- No swap framing. Removal of `remember` is unrelated to adoption of `context-mode` -- both happen to be `enabledPlugins` edits.
- No statusline change. The custom `claude/.claude/statusline.sh` (token-usage display) is preserved. The `context-mode statusline` option from the plugin docs is declined.
- No `ce-compound` run. Per project CLAUDE.md, quick fixes may skip `ce-compound`; this is a 2-line config edit with no novel learnings to compound.
- No PR. No-pr mode default per project CLAUDE.md. Workflow ends at `finishing-a-development-branch` option 1 (local merge -> push main).

## Architecture

`context-mode` is a runtime plugin distributed via the `mksglu/context-mode` GitHub marketplace. Per its install docs it **auto-registers** an MCP server and 5 hooks (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `PreCompact`, `SessionStart`) via its plugin manifest. None of these registrations land in `settings.base.json` -- they live in the plugin's own manifest under `~/.claude/plugins/cache/.../context-mode/`.

The only stowed-config surface that needs editing is the `enabledPlugins` toggle in `claude/.claude/settings.base.json` lines 275-281. Everything else (marketplace registration, plugin install) happens at runtime via slash commands the user executes in the REPL.

Hook collisions are theoretically possible -- the dotfiles repo already registers `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SessionEnd` hooks via `settings.base.json`. The plugin docs explicitly state hooks merge by matcher, and `/context-mode:ctx-doctor` is the diagnostic path if collisions surface.

`PreCompact` was idle in the project since wiki-capture removal during the prior superpowers reorg. It will fire again, this time from `context-mode` itself, not the silently-broken WIKI_VAULT path. Accepted side effect.

## File changes

### `claude/.claude/settings.base.json`

Two edits to the `enabledPlugins` block (currently lines 275-281):

**Edit A -- remove disabled `remember` entry.**

Before:
```json
  "enabledPlugins": {
    "claude-md-management@claude-plugins-official": true,
    "remember@claude-plugins-official": false,
    "caveman@caveman": true,
    "superpowers@superpowers-marketplace": true,
    "compound-engineering@compound-engineering-plugin": true
  }
```

After:
```json
  "enabledPlugins": {
    "claude-md-management@claude-plugins-official": true,
    "caveman@caveman": true,
    "superpowers@superpowers-marketplace": true,
    "compound-engineering@compound-engineering-plugin": true
  }
```

**Edit B -- alphabetize `enabledPlugins` entries.**

Sort the four remaining keys alphabetically. Pure reordering -- no add, no remove, no value change. Makes Edit C's insertion position obvious.

Before:
```json
  "enabledPlugins": {
    "claude-md-management@claude-plugins-official": true,
    "caveman@caveman": true,
    "superpowers@superpowers-marketplace": true,
    "compound-engineering@compound-engineering-plugin": true
  }
```

After:
```json
  "enabledPlugins": {
    "caveman@caveman": true,
    "claude-md-management@claude-plugins-official": true,
    "compound-engineering@compound-engineering-plugin": true,
    "superpowers@superpowers-marketplace": true
  }
```

**Edit C -- enable `context-mode` plugin.**

Insert in alphabetical position between `compound-engineering` and `superpowers`.

Before:
```json
  "enabledPlugins": {
    "caveman@caveman": true,
    "claude-md-management@claude-plugins-official": true,
    "compound-engineering@compound-engineering-plugin": true,
    "superpowers@superpowers-marketplace": true
  }
```

After:
```json
  "enabledPlugins": {
    "caveman@caveman": true,
    "claude-md-management@claude-plugins-official": true,
    "compound-engineering@compound-engineering-plugin": true,
    "context-mode@context-mode": true,
    "superpowers@superpowers-marketplace": true
  }
```

Plugin-key format `<plugin>@<marketplace>` per `/plugin install context-mode@context-mode` from upstream docs. The marketplace key `context-mode` is the default ID produced by `/plugin marketplace add mksglu/context-mode` (the GitHub repo slug). If the actual marketplace ID differs after add, the key must match the value shown by `/plugin marketplace list` -- adjust in a follow-up commit if so.

### `~/.claude/settings.json`

Gitignored. Regenerated by `claude-sync` from `settings.base.json` + `~/workspace/claude-skills/settings.overlay.json`. No manual edit. Verified to contain `context-mode@context-mode: true` after run.

## Commits

Three atomic commits on `worktree-context-mode-install`:

```
A  chore(claude): remove disabled remember plugin entry
B  refactor(claude): alphabetize enabledPlugins
C  feat(claude): enable context-mode plugin
```

Each independently revertable via `git revert <sha>` + `claude-sync`. Per the project `feedback-atomic-commits-pr` convention.

Type rationale: `chore` for removing dead config, `refactor` for pure reordering (no behavior change), `feat` for enabling new plugin functionality.

## User-run REPL commands (out-of-band)

These slash commands are not bash; they execute inside the Claude Code REPL and write to runtime state under `~/.claude/plugins/`, not to any tracked file. They must be run by the user once per machine (Stow does not propagate runtime plugin state). Run them after Commit C and before the `claude-sync` verify step:

```
/plugin marketplace add mksglu/context-mode
/plugin install context-mode@context-mode
```

If the marketplace add succeeds but uses a different marketplace ID, the `enabledPlugins` key in Edit C must match. Diagnose with `/plugin marketplace list`.

## Verification

After all three commits land + REPL commands run:

1. Run `claude-sync` from the worktree. Confirm exit 0.
2. Run `jq .enabledPlugins ~/.claude/settings.json` -- expect:
   - `context-mode@context-mode: true` present.
   - No `remember@claude-plugins-official` key.
   - Keys ordered alphabetically: `caveman`, `claude-md-management`, `compound-engineering`, `context-mode`, `superpowers`.
   - All five entries set to `true`.
3. Restart the Claude Code session in the worktree.
4. Run `/context-mode:ctx-doctor` -- expect a healthy report (no missing hooks, MCP server reachable).
5. Confirm existing workflow unchanged:
   - Statusline still renders token usage from custom `statusline.sh`.
   - Existing git hooks (`git-session-start.sh`, `worktree-exited.sh`, etc.) still fire.
   - Existing superpowers + compound-engineering skills still invokable.

If any verification fails, revert offending commit and diagnose before retry.

## Risks

1. **Marketplace ID mismatch.** `/plugin marketplace add mksglu/context-mode` may assign a marketplace ID different from `context-mode`. Mitigation: check `/plugin marketplace list`; correct the `enabledPlugins` key in a follow-up commit if needed.
2. **Hook collision.** Plugin auto-registration may conflict with existing `settings.base.json` hooks at the same matcher. Mitigation: `/context-mode:ctx-doctor` flags collisions; resolve per plugin docs.
3. **PreCompact return.** Plugin re-introduces `PreCompact` after it had been idle since the wiki-capture removal. Mitigation: accepted -- this time the hook is owned by `context-mode` and is intended to fire.
4. **MCP server startup.** `context-mode` MCP server must reach its dependencies on first run. Mitigation: `/context-mode:ctx-doctor` diagnoses; `CONTEXT_MODE_STARTUP_SWEEP=1` default reaps any orphaned siblings.

## Workflow

```
EnterWorktree("context-mode-install")  -- done
  ↓
brainstorming (this spec)
  ↓
writing-plans -> docs/superpowers/plans/2026-05-19-context-mode-plugin-install.md
  ↓
subagent-driven-development (2 commits)
  ↓
verification-before-completion (jq + ctx-doctor)
  ↓
requesting-code-review (loop until clean)
  ↓
finishing-a-development-branch option 1 (local merge -> push main)
  ↓
ExitWorktree("keep")
```

`ce-compound` deliberately omitted.

## Related

- Prior reorg: `docs/superpowers/specs/2026-05-19-superpowers-workflow-reorg-design.md` -- established the canonical superpowers + compound-engineering chain this work follows.
- Solution doc: `docs/solutions/workflow-issues/superpowers-workflow-reorg-2026-05-19.md` -- captures the broader workflow context.
- Upstream plugin: `https://github.com/mksglu/context-mode` (ELv2 license).
