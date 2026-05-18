# Superpowers workflow reorganization — design

**Date:** 2026-05-19
**Branch:** `worktree-superpowers-workflow-reorg`
**Status:** Approved by user, pending implementation plan

## Goal

Reorganize the Claude workflow around the superpowers skill chain
(brainstorming → writing-plans → subagent-driven-development →
requesting-code-review → finishing-a-development-branch), with
`compound-engineering:ce-compound` as the final knowledge-capture step
before merge. Remove plugins, docs, and CLAUDE.md sections that no longer
fit.

## Canonical workflow (after reorg)

```
EnterWorktree (hook-enforced)
   ↓
brainstorming   →  docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md  (committed in worktree)
   ↓
writing-plans   →  plan file  (committed in worktree)
   ↓
subagent-driven-development  (+ TDD + systematic-debugging inline)
   ↓
verification-before-completion
   ↓
requesting-code-review  (re-invoke after fixes until clean)
   ↓
ce-compound     →  docs/solutions/<...>.md  (committed in worktree)
   ↓
finishing-a-development-branch
   ├─ no-pr default: option 1 (local merge → push main)
   └─ PR mode: ce-commit-push-pr → ce-resolve-pr-feedback
```

### Key invariants

1. **EnterWorktree first.** All plan artifacts (spec, plan, ce-compound
   doc) must be written inside the worktree and committed to the worktree
   branch alongside implementation. They land on main when the feature
   merges. Rationale: keeps design+plan+learnings tied to implementation
   in git history; avoids polluting main with WIP; never lose artifacts
   to temp dirs.
2. **No-pr is default.** `finishing-a-development-branch` option 1
   (local merge) is the default integration path. PR mode is opt-in.
3. **PR mode uses ce, not superpowers light path.** When a PR is needed,
   use `compound-engineering:ce-commit-push-pr` (adaptive value-first
   description) + `ce-resolve-pr-feedback` (review thread resolution).
   The lighter `finishing-a-development-branch` option 2 is documented
   but not the preferred PR path.
4. **ce-compound runs in the worktree before finishing.** Documents the
   solution while context is fresh; the `docs/solutions/<...>.md` ships
   with the feature commits.

## Plugin matrix (after)

| Plugin                                            | State                | Role                          |
| ------------------------------------------------- | -------------------- | ----------------------------- |
| `superpowers@superpowers-marketplace`             | enabled              | Primary workflow skills       |
| `compound-engineering@compound-engineering-plugin`| **newly declared**   | ce-compound + PR helpers      |
| `caveman@caveman`                                 | enabled              | Token compression mode        |
| `claude-md-management@claude-plugins-official`    | enabled              | CLAUDE.md tooling             |
| `remember@claude-plugins-official`                | disabled (unchanged) | —                             |
| `commit-commands@claude-plugins-official`         | **removed**          | Replaced by superpowers + ce  |
| `feature-dev@claude-plugins-official`             | **removed**          | Replaced by subagent-driven-dev |
| `ralph-loop@claude-plugins-official`              | **removed**          | Unused                        |
| local `claude/.claude/plugins/pr/`                | already extracted    | Was moved to `benkim0414/skills` in commit `58762e3`; the external `pr@skills` plugin replaces it and gets implicitly disabled when `enabledPlugins` is rewritten + `claude-sync` runs |
| stale `plugins/pr/` ref in `dotfiles/CLAUDE.md:48` | **edited**           | Cleanup of stale doc text     |

## Hooks (after)

11 hooks retained, all workflow-agnostic safety/UX. Audited individually
during brainstorm; none tied to the old PR flow.

| #  | Hook                       | Event                            | Retained? |
| -- | -------------------------- | -------------------------------- | --------- |
| 1  | `git-session-start.sh`     | SessionStart                     | ✓         |
| 2  | `resolve-pr-refs.sh`       | UserPromptSubmit                 | ✓         |
| 3  | `read-once.sh`             | PreToolUse (Read/Bash/Grep/etc)  | ✓         |
| 4  | `git-safety.sh`            | PreToolUse (Bash)                | ✓         |
| 5  | `worktree-guard.sh`        | PreToolUse (Write/Edit)          | ✓         |
| 6  | `notify.sh`                | PreToolUse + Notification        | ✓         |
| 7  | `worktree-entered.sh`      | PostToolUse (EnterWorktree)      | ✓         |
| 8  | `worktree-exited.sh`       | PostToolUse (ExitWorktree)       | ✓         |
| 9  | `audit-log.sh`             | PostToolUse async                | ✓         |
| 10 | `failure-recovery.sh`      | PostToolUseFailure               | ✓         |
| 11 | `restore-git-context.sh`   | PostCompact                      | ✓         |
| 12 | `capture-session-to-wiki.sh` | PreCompact + SessionEnd        | **deleted** |

`capture-session-to-wiki.sh` is removed because `WIKI_VAULT` in
`settings.base.json` pointed to a Linux path (`/home/benkim0414/...`)
on a macOS box. The hook has been silently failing. Decision: drop
wiki capture entirely rather than fix the path.

## Docs (after)

| File                                              | Action      |
| ------------------------------------------------- | ----------- |
| `claude/.claude/docs/bootstrap.md`                | unchanged   |
| `claude/.claude/docs/no-pr-review.md`             | **deleted** |
| `claude/.claude/docs/superpowers-workflow.md`     | **rewritten** |
| `claude/.claude/CLAUDE.md`                        | **rewritten** |

### `superpowers-workflow.md` rewrite scope

- New canonical flow diagram (above)
- Skill purpose table
- Artifact placement rule (worktree, committed with feature)
- ce-compound role at end
- PR-mode alternative pointing to ce-commit-push-pr + ce-resolve-pr-feedback
- Remove obsolete references to plan-mode vs writing-plans distinction
  (writing-plans now subsumes it)

### `CLAUDE.md` rewrite scope

Delete:
- "Superpowers integration" ban list (third paragraph onward — removes
  bans on subagent-driven-development, finishing-a-development-branch,
  requesting-code-review, receiving-code-review)
- "Wiki capture" section
- References to `/pr:create`, `/pr:address`, `/pr:merge`

Rewrite:
- "Git Workflow" section:
  - No-pr default: `superpowers:requesting-code-review` (dispatches
    `superpowers:code-reviewer` subagent; re-invoke after each fix
    batch until clean) instead of `~/.claude/docs/no-pr-review.md`
    two-agent loop
  - PR mode: `compound-engineering:ce-commit-push-pr` instead of
    `/pr:create`; `ce-resolve-pr-feedback` instead of `/pr:address`
  - `ce-compound` runs before `finishing-a-development-branch`
- Reference updated `~/.claude/docs/superpowers-workflow.md`

Keep:
- Preferences (editor, no emojis, never assume)
- Response style
- Verification & context
- Semantic Search (qmd)

## Commit sequence

Six conventional commits on `worktree-superpowers-workflow-reorg`. Each
self-contained and revertable.

1. **`chore(claude): remove unused plugins`**
   - Edit `claude/.claude/settings.base.json`:
     - Remove `commit-commands`, `feature-dev`, `ralph-loop` from
       `enabledPlugins`
     - Add `compound-engineering@compound-engineering-plugin: true`
   - Note: `claude-sync` regenerates `~/.claude/settings.json`; the
     generated file is gitignored, so no commit there.

2. **`docs(dotfiles): drop stale local pr plugin reference`**
   - Edit `/Users/ben/workspace/dotfiles/CLAUDE.md:48`: the line
     `The plugins/pr/ subtree is a local Claude Code plugin; see the
     plugin section above for activation.` is stale — the local plugin
     was extracted to `benkim0414/skills` in commit `58762e3`. Replace
     with text noting that `pr@skills` (external) is no longer enabled
     under the superpowers-first workflow; PR mechanics go through
     `compound-engineering:ce-commit-push-pr` instead.

3. **`chore(claude): drop wiki capture hook + WIKI_VAULT`**
   - Edit `claude/.claude/settings.base.json`:
     - Remove `WIKI_VAULT` from `env`
     - Remove `PreCompact` array entry pointing to capture-session-to-wiki
     - Remove `SessionEnd` array entry pointing to capture-session-to-wiki
   - `rm claude/.claude/hooks/capture-session-to-wiki.sh`

4. **`docs(claude): delete no-pr-review rubric`**
   - `rm claude/.claude/docs/no-pr-review.md`

5. **`docs(claude): rewrite superpowers-workflow.md`**
   - Full rewrite per scope above

6. **`docs(claude): rewrite CLAUDE.md for superpowers-first workflow`**
   - Per scope above

Spec doc (this file) and the writing-plans output land in a separate
`docs(spec): superpowers workflow reorg` commit at the start of the
sequence, or are folded into commit 1 — to be decided in the plan.

## Verification

After all commits, on the worktree branch:

```bash
# Regenerate settings
claude-sync

# Plugin matrix
jq '.enabledPlugins' ~/.claude/settings.json

# Expected: caveman, claude-md-management, compound-engineering,
# superpowers = true; remember = false; no commit-commands/feature-dev/
# ralph-loop keys present

# Env clean
jq '.env.WIKI_VAULT' ~/.claude/settings.json   # → null

# pr@skills implicitly disabled (not in base + not in overlay)
jq '.enabledPlugins | has("pr@skills")' ~/.claude/settings.json   # → false

# Files deleted
[ ! -f claude/.claude/hooks/capture-session-to-wiki.sh ] && echo "wiki hook gone"
[ ! -f claude/.claude/docs/no-pr-review.md ] && echo "no-pr doc gone"

# Stale ref cleaned
grep -c "plugins/pr/" /Users/ben/workspace/dotfiles/CLAUDE.md   # → 0

# Hook count = 11
ls claude/.claude/hooks/*.sh | wc -l   # → 11

# settings.base.json has no wiki references
grep -c 'capture-session-to-wiki\|WIKI_VAULT' claude/.claude/settings.base.json   # → 0

# CLAUDE.md cleaned
grep -c 'Do NOT use superpowers\|Wiki capture' claude/.claude/CLAUDE.md   # → 0

# Commit log
git log --oneline main..HEAD   # → 6 conventional commits + 1 spec commit
```

## Out of scope

- Refactoring or extending superpowers / compound-engineering skills themselves
- Changing the 11 retained hooks
- Touching permissions block in `settings.base.json`
- Modifying `statusline.sh`, lib/, or themes/
- Adding new skills under `claude/.claude/skills/`
- Changing how `~/workspace/claude-skills/settings.overlay.json` works
  (work-specific overlay remains untouched)

## Open decisions for the plan

1. Whether the spec + plan commit lands as its own `docs(spec): ...`
   commit at the start of the sequence, or is folded into commit 1.
2. Whether `claude-sync` runs once at the end of the sequence or after
   each settings.base.json-touching commit.
3. Whether to verify with `claude` CLI plugin-listing after the reorg
   to confirm runtime accepts the new `enabledPlugins` shape.

## Rollback

Each commit is independent. To revert any single change:

```bash
git revert <commit-sha>
claude-sync
```

To revert the entire reorganization:

```bash
git checkout main
git branch -D worktree-superpowers-workflow-reorg
git worktree remove .claude/worktrees/superpowers-workflow-reorg
```

No external state changes — fully local rollback.
