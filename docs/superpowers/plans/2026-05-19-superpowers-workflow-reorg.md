# Superpowers Workflow Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the dotfiles claude package around superpowers + compound-engineering so feature work flows: EnterWorktree → brainstorming → writing-plans → subagent-driven-development → requesting-code-review → ce-compound → finishing-a-development-branch. Remove plugins, docs, and CLAUDE.md sections that no longer fit.

**Architecture:** Six atomic conventional commits, each independently revertable. Spec already committed (`docs/superpowers/specs/2026-05-19-superpowers-workflow-reorg-design.md`). Work happens on worktree branch `worktree-superpowers-workflow-reorg`. The repo has no automated tests — verification is shell-grep + jq probes.

**Tech Stack:** `jq` for JSON edits, `git` for atomic commits, shell for verification. No code compiled. `claude-sync` script regenerates the merged `~/.claude/settings.json` from `settings.base.json` + `settings.overlay.json`.

---

## File Structure

Files modified, in commit order:

| Commit | File                                            | Action  |
| ------ | ----------------------------------------------- | ------- |
| 1      | `claude/.claude/settings.base.json`             | edit (enabledPlugins) |
| 2      | `CLAUDE.md` (project root)                      | edit (line 48 stale ref) |
| 3      | `claude/.claude/settings.base.json`             | edit (env + hooks) |
| 3      | `claude/.claude/hooks/capture-session-to-wiki.sh` | delete file |
| 4      | `claude/.claude/docs/no-pr-review.md`           | delete file |
| 5      | `claude/.claude/docs/superpowers-workflow.md`   | rewrite |
| 6      | `claude/.claude/CLAUDE.md`                      | rewrite |

The spec doc and this plan doc were committed in `docs(spec): superpowers workflow reorganization design` (commit `d614221`) before this plan starts. No additional plan/spec commits during the six reorg tasks.

---

## Task 1: Remove unused plugins from settings.base.json

**Files:**
- Modify: `claude/.claude/settings.base.json` (the `enabledPlugins` object)

### Steps

- [ ] **Step 1: Inspect current enabledPlugins**

Run:
```bash
jq '.enabledPlugins' claude/.claude/settings.base.json
```

Expected output:
```json
{
  "claude-md-management@claude-plugins-official": true,
  "commit-commands@claude-plugins-official": true,
  "feature-dev@claude-plugins-official": true,
  "ralph-loop@claude-plugins-official": true,
  "remember@claude-plugins-official": false,
  "caveman@caveman": true,
  "superpowers@superpowers-marketplace": true
}
```

- [ ] **Step 2: Rewrite enabledPlugins via jq**

Run:
```bash
jq '.enabledPlugins = {
  "claude-md-management@claude-plugins-official": true,
  "remember@claude-plugins-official": false,
  "caveman@caveman": true,
  "superpowers@superpowers-marketplace": true,
  "compound-engineering@compound-engineering-plugin": true
}' claude/.claude/settings.base.json > claude/.claude/settings.base.json.tmp
mv claude/.claude/settings.base.json.tmp claude/.claude/settings.base.json
```

- [ ] **Step 3: Verify the new enabledPlugins**

Run:
```bash
jq '.enabledPlugins' claude/.claude/settings.base.json
```

Expected output:
```json
{
  "claude-md-management@claude-plugins-official": true,
  "remember@claude-plugins-official": false,
  "caveman@caveman": true,
  "superpowers@superpowers-marketplace": true,
  "compound-engineering@compound-engineering-plugin": true
}
```

Then verify removed keys are gone:
```bash
jq '.enabledPlugins | has("commit-commands@claude-plugins-official"),
                       has("feature-dev@claude-plugins-official"),
                       has("ralph-loop@claude-plugins-official"),
                       has("compound-engineering@compound-engineering-plugin")' \
   claude/.claude/settings.base.json
```

Expected output:
```
false
false
false
true
```

- [ ] **Step 4: Verify JSON still parses cleanly**

Run:
```bash
jq empty claude/.claude/settings.base.json && echo "VALID"
```

Expected output: `VALID` (no jq errors).

- [ ] **Step 5: Commit**

Run:
```bash
git add claude/.claude/settings.base.json
git commit -m "chore(claude): swap unused plugins for compound-engineering

Drop commit-commands, feature-dev, ralph-loop (replaced by superpowers
+ compound-engineering skill chain). Declare compound-engineering for
ce-compound, ce-commit-push-pr, ce-resolve-pr-feedback."
```

---

## Task 2: Drop stale local pr plugin reference in dotfiles/CLAUDE.md

The local `claude/.claude/plugins/pr/` directory was extracted to
`benkim0414/skills` in commit `58762e3`, so there is nothing to
delete in the dotfiles tree. The external `pr@skills` plugin
replaces it at runtime, but is NOT declared in
`claude/.claude/settings.base.json` -- Task 1's rewrite of
`enabledPlugins` will implicitly drop it on next `claude-sync`.

What remains is a stale text reference in the project-root
`/Users/ben/workspace/dotfiles/CLAUDE.md` (line 48) pointing to
the no-longer-present local plugin. This task cleans that up.

**Files:**
- Modify: `/Users/ben/workspace/dotfiles/CLAUDE.md` (line 48)

### Steps

- [ ] **Step 1: Confirm the stale reference**

Run:
```bash
grep -n "plugins/pr" /Users/ben/workspace/dotfiles/CLAUDE.md
```

Expected output (line number may shift, content should match):
```
48:- The `claude/` package stows to `~/.claude/` (hooks, rules, plugins, and project instructions). `settings.json` is generated by `claude-sync` -- not stowed directly. The `plugins/pr/` subtree is a local Claude Code plugin; see the plugin section above for activation.
```

If the file already lacks any `plugins/pr` reference, skip to Step 4 (nothing to commit).

- [ ] **Step 2: Edit the line in place**

Using the `Edit` tool with absolute path
`/Users/ben/workspace/dotfiles/CLAUDE.md`, replace this exact text:

```
- The `claude/` package stows to `~/.claude/` (hooks, rules, plugins, and project instructions). `settings.json` is generated by `claude-sync` -- not stowed directly. The `plugins/pr/` subtree is a local Claude Code plugin; see the plugin section above for activation.
```

with this exact text:

```
- The `claude/` package stows to `~/.claude/` (hooks, rules, plugins, and project instructions). `settings.json` is generated by `claude-sync` -- not stowed directly. PR mechanics go through `compound-engineering:ce-commit-push-pr` and `ce-resolve-pr-feedback`; the local `pr/` plugin was extracted to `benkim0414/skills` in commit `58762e3` and the `pr@skills` external replacement is no longer declared in `settings.base.json`.
```

- [ ] **Step 3: Verify the edit landed**

Run:
```bash
grep -c "plugins/pr" /Users/ben/workspace/dotfiles/CLAUDE.md
grep -c "compound-engineering:ce-commit-push-pr" /Users/ben/workspace/dotfiles/CLAUDE.md
```

Expected output:
```
0
1
```

- [ ] **Step 4: Commit**

Note: this edit is to the file at the repo root, not under `claude/.claude/`. The same worktree branch covers both paths because the repo IS the dotfiles root.

```bash
git add CLAUDE.md
git commit -m "docs(dotfiles): drop stale local pr plugin reference

The local plugins/pr/ subtree was extracted to benkim0414/skills in
commit 58762e3. The external pr@skills replacement is intentionally
not declared in settings.base.json under the superpowers-first
workflow -- PR mechanics route through compound-engineering instead."
```

---

## Task 3: Drop wiki capture hook + WIKI_VAULT env

**Files:**
- Modify: `claude/.claude/settings.base.json` (env, hooks.PreCompact, hooks.SessionEnd)
- Delete: `claude/.claude/hooks/capture-session-to-wiki.sh`

### Steps

- [ ] **Step 1: Inspect current env + hooks**

Run:
```bash
jq '{env, preCompact: .hooks.PreCompact, sessionEnd: .hooks.SessionEnd}' claude/.claude/settings.base.json
```

Expected output:
```json
{
  "env": {
    "DISABLE_COST_WARNINGS": "1",
    "WIKI_VAULT": "/home/benkim0414/workspace/wiki"
  },
  "preCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash $HOME/.claude/hooks/capture-session-to-wiki.sh",
          "async": true
        }
      ]
    }
  ],
  "sessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash $HOME/.claude/hooks/capture-session-to-wiki.sh",
          "async": true
        }
      ]
    }
  ]
}
```

Both arrays contain only the wiki hook, so removing them empties both. We will delete the keys entirely rather than leave empty arrays.

- [ ] **Step 2: Remove WIKI_VAULT, PreCompact, SessionEnd via jq**

Run:
```bash
jq 'del(.env.WIKI_VAULT) |
    del(.hooks.PreCompact) |
    del(.hooks.SessionEnd)' \
   claude/.claude/settings.base.json > claude/.claude/settings.base.json.tmp
mv claude/.claude/settings.base.json.tmp claude/.claude/settings.base.json
```

- [ ] **Step 3: Verify env + hooks are clean**

Run:
```bash
jq '.env.WIKI_VAULT' claude/.claude/settings.base.json
jq '.hooks | has("PreCompact"), has("SessionEnd")' claude/.claude/settings.base.json
```

Expected output:
```
null
false
false
```

Verify PostCompact (different key, retained) still has `restore-git-context.sh`:
```bash
jq '.hooks.PostCompact' claude/.claude/settings.base.json
```

Expected output: non-null array containing `restore-git-context.sh`. If it's null, something went wrong — revert.

- [ ] **Step 4: Delete the hook script**

Run:
```bash
rm claude/.claude/hooks/capture-session-to-wiki.sh
[ ! -f claude/.claude/hooks/capture-session-to-wiki.sh ] && echo "GONE"
```

Expected output: `GONE`.

- [ ] **Step 5: Verify hook count = 11**

Run:
```bash
ls claude/.claude/hooks/*.sh | wc -l
```

Expected output: `11`.

- [ ] **Step 6: Validate JSON**

Run:
```bash
jq empty claude/.claude/settings.base.json && echo "VALID"
```

Expected output: `VALID`.

- [ ] **Step 7: Commit**

Run:
```bash
git add claude/.claude/settings.base.json claude/.claude/hooks/capture-session-to-wiki.sh
git commit -m "chore(claude): drop wiki capture hook and WIKI_VAULT env

The hook was silently failing -- WIKI_VAULT pointed to a Linux path
(/home/benkim0414/workspace/wiki) on the macOS box. Rather than fix the
path, drop the wiki-capture flow entirely. Removes the capture script,
the WIKI_VAULT env var, and the PreCompact + SessionEnd hook arrays
(both contained only this one hook)."
```

---

## Task 4: Delete no-pr-review.md rubric

**Files:**
- Delete: `claude/.claude/docs/no-pr-review.md`

### Steps

- [ ] **Step 1: Confirm file exists**

Run:
```bash
[ -f claude/.claude/docs/no-pr-review.md ] && echo "EXISTS"
```

Expected output: `EXISTS`. If missing, the file was already removed — skip to Step 4.

- [ ] **Step 2: Verify no remaining references in checked-in files**

Run:
```bash
grep -rn "no-pr-review" claude/.claude/ --include="*.md" --include="*.json" --include="*.sh"
```

Expected: matches in `CLAUDE.md` and possibly elsewhere — these will be cleaned up in Task 6 (CLAUDE.md rewrite) and Task 5 (superpowers-workflow.md rewrite). The file itself can be deleted now; downstream rewrites will remove the references.

Note for reviewer: the references-vs-deletion gap is intentional. We delete the rubric in commit 4 and the references to it in commits 5+6. This means at commits 4 and 5 the docs reference a missing file. Acceptable because all three changes ship together before merge.

- [ ] **Step 3: Delete the file**

Run:
```bash
rm claude/.claude/docs/no-pr-review.md
[ ! -f claude/.claude/docs/no-pr-review.md ] && echo "GONE"
```

Expected output: `GONE`.

- [ ] **Step 4: Commit**

Run:
```bash
git add claude/.claude/docs/no-pr-review.md
git commit -m "docs(claude): delete no-pr-review rubric

The two-agent review loop using feature-dev:code-reviewer is replaced
by superpowers:requesting-code-review (which dispatches
superpowers:code-reviewer per invocation; re-invoke after fixes until
clean). CLAUDE.md references to no-pr-review.md are removed in a
follow-up commit."
```

---

## Task 5: Rewrite superpowers-workflow.md

**Files:**
- Modify: `claude/.claude/docs/superpowers-workflow.md` (full replacement)

### Steps

- [ ] **Step 1: Inspect current file**

Run:
```bash
wc -l claude/.claude/docs/superpowers-workflow.md
```

Expected: ~94 lines (current version, before rewrite).

- [ ] **Step 2: Replace file contents**

Overwrite the file with this exact content:

````markdown
# Superpowers + compound-engineering workflow

The canonical workflow for feature work and debugging. Skills auto-trigger
by context; explicit invocation via `/superpowers:<skill>` or
`/compound-engineering:<skill>`.

## Feature development

```
EnterWorktree                  ← hook-enforced isolation; ALL plan artifacts live here
    ↓
brainstorming                  ← design + Socratic clarification
    ↓                             → docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md
writing-plans                  ← step-by-step breakdown
    ↓                             → docs/superpowers/plans/YYYY-MM-DD-<topic>.md
subagent-driven-development    ← parallel implementation
    ↓                             (TDD + systematic-debugging inline)
verification-before-completion ← claims gate
    ↓
requesting-code-review         ← dispatch superpowers:code-reviewer subagent
    ↓                             (re-invoke after each fix batch until clean)
ce-compound                    ← document learnings
    ↓                             → docs/solutions/<...>.md
finishing-a-development-branch ← integrate
   ├─ no-pr default: option 1 (local merge → push main)
   └─ PR mode:       compound-engineering:ce-commit-push-pr
                     compound-engineering:ce-resolve-pr-feedback
```

### Artifact placement

All plan artifacts -- brainstorm spec, writing-plans output, ce-compound
solution doc -- are written inside the worktree and committed to the
worktree branch alongside implementation. They land on main when the
feature merges. Keeps design + plan + learnings tied to implementation
in git history.

### When each skill fires

| Skill | Auto-triggers when |
|---|---|
| `brainstorming` | Asked to create/design something new |
| `writing-plans` | Have a spec/requirements for multi-step work |
| `subagent-driven-development` | Have a plan with independent tasks |
| `test-driven-development` | About to implement a feature or bugfix |
| `systematic-debugging` | Investigating a bug, test failure, or unexpected behavior |
| `verification-before-completion` | About to claim something is done/fixed |
| `requesting-code-review` | Implementation complete, before merge |
| `ce-compound` | Solution is correct + review-clean, ready to capture |
| `finishing-a-development-branch` | All gates passed, ready to integrate |

---

## Debugging

```
systematic-debugging           ← any bug, test failure, or unexpected behavior
    ↓
EnterWorktree
    ↓
test-driven-development        ← failing test that reproduces the bug
    ↓
fix
    ↓
verification-before-completion
    ↓
requesting-code-review
    ↓
ce-compound                    ← capture root cause + fix for future
    ↓
finishing-a-development-branch
```

`systematic-debugging` runs a 4-phase process:
1. Reproduce and isolate
2. Trace root cause (not symptoms)
3. Validate the fix hypothesis
4. Defend against recurrence

---

## Quick fix (no design phase)

```
EnterWorktree → test-driven-development → fix →
verification-before-completion → requesting-code-review →
finishing-a-development-branch
```

Skip `brainstorming` and `writing-plans` for single-file or trivial
fixes. `ce-compound` is optional for quick fixes -- only invoke if the
fix has reusable lessons worth capturing.

---

## Notes

- `brainstorming` is Socratic -- it asks questions to refine the design
  before committing to an approach. Let it run before opening a worktree
  if no worktree exists yet, otherwise it runs inside the worktree.
- `subagent-driven-development` dispatches a fresh subagent per task
  with two-stage review between tasks. Faster iteration than inline
  `executing-plans` for plans with independent tasks.
- `verification-before-completion` is a pre-report gate, not a
  post-merge check. Run it before saying "done" or "fixed".
- `requesting-code-review` dispatches `superpowers:code-reviewer`
  subagent per invocation. To loop, re-invoke after each fix batch.
- `ce-compound` runs in the worktree, writing to `docs/solutions/`. The
  doc merges to main with the feature commits.
- `finishing-a-development-branch` runs tests first; never proceeds if
  tests fail. Option 1 = local merge, option 2 = PR via `gh pr create`,
  option 3 = keep as-is, option 4 = discard. Prefer option 1 for no-pr
  mode; for PR mode, use `ce-commit-push-pr` instead of option 2 for
  richer descriptions.
````

Use the `Write` tool with the absolute path
`/Users/ben/workspace/dotfiles/.claude/worktrees/superpowers-workflow-reorg/claude/.claude/docs/superpowers-workflow.md`
and the content block above (everything between the triple-backtick
fences in Step 2, NOT including the fences themselves).

- [ ] **Step 3: Verify the rewrite landed**

Run:
```bash
head -3 claude/.claude/docs/superpowers-workflow.md
```

Expected output:
```
# Superpowers + compound-engineering workflow

The canonical workflow for feature work and debugging. Skills auto-trigger
```

Check no stale references:
```bash
grep -c "no-pr-review\|/pr:create\|/pr:address\|/pr:merge\|feature-dev:code-reviewer" \
  claude/.claude/docs/superpowers-workflow.md
```

Expected output: `0`.

- [ ] **Step 4: Commit**

Run:
```bash
git add claude/.claude/docs/superpowers-workflow.md
git commit -m "docs(claude): rewrite superpowers-workflow.md

New canonical flow: EnterWorktree -> brainstorming -> writing-plans ->
subagent-driven-development -> requesting-code-review -> ce-compound ->
finishing-a-development-branch. Documents artifact-placement rule
(worktree-committed) and PR-mode handoff to compound-engineering."
```

---

## Task 6: Rewrite CLAUDE.md for superpowers-first workflow

**Files:**
- Modify: `claude/.claude/CLAUDE.md` (full replacement)

### Steps

- [ ] **Step 1: Inspect current file**

Run:
```bash
wc -l claude/.claude/CLAUDE.md
```

Expected: ~89 lines.

- [ ] **Step 2: Replace file contents**

Overwrite with this exact content (use `Write` tool with absolute path
`/Users/ben/workspace/dotfiles/.claude/worktrees/superpowers-workflow-reorg/claude/.claude/CLAUDE.md`):

````markdown
# Global Claude Code Preferences

## Preferences

- Editor: nvim
- Never use emojis in responses
- IMPORTANT: Never assume -- if requirements are ambiguous, underspecified, or
  open to multiple interpretations, ask clarifying questions before proceeding.
  This applies to task scope, implementation approach, edge cases, naming, and
  any decision that could go more than one way.

## Response style

- Explain the reasoning behind config choices, not just what to set
- Present the dry-run/plan/diff form of a command before the apply form; let the user review first
- Use the fetch MCP to look up current docs, API versions, or package versions -- training data goes stale; never guess at versions

## Verification & context

- Always verify work before reporting completion -- run the project's test
  suite, linter, type checker, or build command. If none exist, describe what
  manual verification the user should perform.
- When an approach fails, prefer rewind (double-tap Esc) over inline
  correction -- rewinding drops the failed attempt from context.
- Use `/compact <hint>` to focus compaction (e.g., "focus on auth refactor,
  drop test debugging"). Use `/clear` with a written brief for new tasks.

## Semantic Search (qmd)

When qmd is available as an MCP server and the current project has an indexed
collection, prefer qmd `query` over Glob/Grep for finding relevant code.
qmd returns semantically ranked results, which is more effective for:
- Finding implementations by describing what they do (not what they're named)
- Discovering related code across a large codebase
- Answering "where is X handled?" questions

Fall back to Glob/Grep when:
- qmd is not available or the project has no indexed collection
- You need exact string/regex matches (import paths, error messages, symbol names)
- You need to find all occurrences exhaustively (refactoring, renaming)

Never automate `qmd collection add`, `qmd embed`, or `qmd update` --
indexing is always a manual user action.

## Git Workflow

All work happens on isolated worktree branches. Hooks enforce worktree
isolation, main-branch protection, and selective staging -- follow the
`[git-workflow]` context injection at session start.

`EnterWorktree` FIRST. All plan artifacts (brainstorm spec at
`docs/superpowers/specs/`, plan at `docs/superpowers/plans/`,
`ce-compound` solution doc at `docs/solutions/`) live inside the
worktree and merge with the feature.

### Canonical workflow

```
EnterWorktree
    ↓
brainstorming         (design + spec)
    ↓
writing-plans         (step-by-step plan)
    ↓
subagent-driven-development     (TDD + systematic-debugging inline)
    ↓
verification-before-completion
    ↓
requesting-code-review          (re-invoke after fixes until clean)
    ↓
ce-compound                     (capture learnings -> docs/solutions/)
    ↓
finishing-a-development-branch
   ├─ no-pr default: option 1 (local merge -> push main)
   └─ PR mode:       compound-engineering:ce-commit-push-pr +
                     compound-engineering:ce-resolve-pr-feedback
```

Full integration details: `~/.claude/docs/superpowers-workflow.md`

### Commit rules

- Commit each self-contained logical change atomically.
- Conventional commits: `type(scope): description` -- types: feat, fix,
  docs, chore, refactor, test, ci, perf.
- Stage specific files; never `git add -A` or `git add .` (hook-enforced).

### No-pr mode (default)

After implementation + `requesting-code-review` is clean +
`ce-compound` has documented the solution: invoke
`finishing-a-development-branch`, pick option 1 (local merge). Then
push main. No PR created.

### PR mode (opt-in)

When a PR is needed:

- `compound-engineering:ce-commit-push-pr` -- commit, push, and open
  the PR with an adaptive value-first description (replaces older
  `/pr:create`).
- `compound-engineering:ce-resolve-pr-feedback` -- address review
  threads (replaces older `/pr:address`).
- After merge: `ExitWorktree("keep")` to return to main.
- YOU MUST use merge commits (`gh pr merge --merge`), never squash or
  rebase.

### Worktree exit

- `ExitWorktree("keep")` after merge (default).
- `ExitWorktree("remove")` only for exploratory work with no commits.

## Plugin integration

`superpowers@superpowers-marketplace` and
`compound-engineering@compound-engineering-plugin` are both enabled.
Skill chain documented above.

Caveats:

- Worktree management uses the harness `EnterWorktree` / `ExitWorktree`
  tools (hook-enforced) -- NOT `superpowers:using-git-worktrees`.
- Parallel agents: use `caveman:cavecrew` for compressed delegation
  when context budget matters; use
  `superpowers:dispatching-parallel-agents` for the standard parallel
  pattern.
- Skill authoring: use the separate `skill-creator` plugin if needed.
````

- [ ] **Step 3: Verify the rewrite landed**

Run:
```bash
head -3 claude/.claude/CLAUDE.md
```

Expected output:
```
# Global Claude Code Preferences

## Preferences
```

Verify obsolete sections are gone:
```bash
grep -c "Do NOT use superpowers\|Wiki capture\|no-pr-review\|/pr:create\|/pr:address\|/pr:merge" \
  claude/.claude/CLAUDE.md
```

Expected output: `0`.

Verify retained sections are intact:
```bash
grep -c "Editor: nvim\|Never use emojis\|Semantic Search (qmd)\|Canonical workflow" \
  claude/.claude/CLAUDE.md
```

Expected output: `4`.

- [ ] **Step 4: Commit**

Run:
```bash
git add claude/.claude/CLAUDE.md
git commit -m "docs(claude): rewrite CLAUDE.md for superpowers-first workflow

Deletes Superpowers integration ban list (subagent-driven-development,
finishing-a-development-branch, and requesting/receiving-code-review
are no longer forbidden -- they are the new canonical flow). Deletes
Wiki capture section (hook removed in earlier commit). Rewrites Git
Workflow: no-pr default uses requesting-code-review; PR mode uses
ce-commit-push-pr + ce-resolve-pr-feedback. ce-compound runs before
finishing-a-development-branch in both modes."
```

---

## Task 6.5: Drop wiki plugin + obsolete bootstrap doc

Added during Task 1 code-quality review. The wiki ingest skill at
`claude/.claude/plugins/wiki/skills/ingest/SKILL.md:273` references
`feature-dev:code-reviewer` -- a subagent that disappears with the
plugin removal in Task 1. Since Task 3 also drops the wiki capture
hook, and `bootstrap.md` primarily documented now-removed wiki +
pr@skills installs, drop the whole wiki plugin and the bootstrap doc.

**Files:**
- Delete dir: `claude/.claude/plugins/wiki/`
- Delete file: `claude/.claude/docs/bootstrap.md`
- Modify: `/Users/ben/workspace/dotfiles/CLAUDE.md` (line 9 stale ref)

### Steps

- [ ] **Step 1: Inspect what's being removed**

Run:
```bash
ls claude/.claude/plugins/wiki/
wc -l claude/.claude/docs/bootstrap.md
grep -n "bootstrap.md" /Users/ben/workspace/dotfiles/CLAUDE.md
```

Expected output:
```
.claude-plugin
skills
     262 claude/.claude/docs/bootstrap.md
9:Fresh-machine setup: `.claude/docs/bootstrap.md`
```

- [ ] **Step 2: Delete + stage with git rm**

```bash
git rm -r claude/.claude/plugins/wiki/
git rm claude/.claude/docs/bootstrap.md
```

- [ ] **Step 3: Edit dotfiles/CLAUDE.md**

Using the `Edit` tool with absolute path
`/Users/ben/workspace/dotfiles/CLAUDE.md`, remove this exact text
(including the trailing blank line):

```
Fresh-machine setup: `.claude/docs/bootstrap.md`

```

with empty string (deletion).

If the surrounding context is also blank, that may produce a double
blank line. Inspect the result with:

```bash
sed -n '5,15p' /Users/ben/workspace/dotfiles/CLAUDE.md
```

Collapse any double blank lines manually if needed (use a second
`Edit` call).

- [ ] **Step 4: Verify deletions + edits**

```bash
[ ! -d claude/.claude/plugins/wiki ]         && echo "wiki-plugin: GONE"
[ ! -f claude/.claude/docs/bootstrap.md ]    && echo "bootstrap-doc: GONE"
grep -c "bootstrap.md" /Users/ben/workspace/dotfiles/CLAUDE.md
```

Expected output:
```
wiki-plugin: GONE
bootstrap-doc: GONE
0
```

- [ ] **Step 5: Stage the CLAUDE.md edit + commit**

```bash
git add CLAUDE.md
git status --short
```

Expected: deletions under `claude/.claude/plugins/wiki/`, deletion of
`claude/.claude/docs/bootstrap.md`, and modification of `CLAUDE.md`.

```bash
git commit -m "chore(claude): drop wiki plugin and obsolete bootstrap doc

The wiki ingest skill at plugins/wiki/skills/ingest/SKILL.md:273
referenced feature-dev:code-reviewer, which is gone after the plugin
removal in commit 71db042. Wiki capture hook was also dropped (commit
in this branch). bootstrap.md primarily documented wiki + pr@skills
installs that are no longer relevant under the superpowers-first
workflow."
```

---

## Final Verification Pass

After all six commits land, run the full verification suite from the
spec. This is a single batch — all checks must pass before invoking
`requesting-code-review`.

- [ ] **Step 1: Regenerate merged settings**

Run:
```bash
claude-sync
echo "exit=$?"
```

Expected output: `exit=0`.

- [ ] **Step 2: Plugin matrix check**

Run:
```bash
jq '.enabledPlugins' ~/.claude/settings.json
```

Expected: object containing
`caveman@caveman: true`,
`claude-md-management@claude-plugins-official: true`,
`compound-engineering@compound-engineering-plugin: true`,
`superpowers@superpowers-marketplace: true`,
`remember@claude-plugins-official: false`,
and NO `commit-commands@*`, `feature-dev@*`, or `ralph-loop@*` keys.

- [ ] **Step 3: Env cleanup check**

Run:
```bash
jq '.env.WIKI_VAULT' ~/.claude/settings.json
```

Expected output: `null`.

- [ ] **Step 4a: pr@skills implicitly disabled**

Run:
```bash
jq '.enabledPlugins | has("pr@skills")' ~/.claude/settings.json
```

Expected output: `false`.

If this returns `true`, the merged settings.json still has `pr@skills`
from a stale source. Re-run `claude-sync` and check again. If still
true, inspect the work overlay at
`/Users/ben/workspace/claude-skills/settings.overlay.json` for any
`enabledPlugins.pr@skills: true` injection.

- [ ] **Step 4b: File deletion checks**

Run:
```bash
[ ! -f claude/.claude/hooks/capture-session-to-wiki.sh ]     && echo "wiki-hook: GONE"
[ ! -f claude/.claude/docs/no-pr-review.md ]                 && echo "no-pr-doc: GONE"
[ ! -d claude/.claude/plugins/wiki ]                         && echo "wiki-plugin: GONE"
[ ! -f claude/.claude/docs/bootstrap.md ]                    && echo "bootstrap-doc: GONE"
```

Expected output:
```
wiki-hook: GONE
no-pr-doc: GONE
wiki-plugin: GONE
bootstrap-doc: GONE
```

- [ ] **Step 4c: Stale refs cleaned**

Run:
```bash
grep -c "plugins/pr/" /Users/ben/workspace/dotfiles/CLAUDE.md
grep -c "bootstrap.md" /Users/ben/workspace/dotfiles/CLAUDE.md
```

Expected output:
```
0
0
```

- [ ] **Step 5: Hook count**

Run:
```bash
ls claude/.claude/hooks/*.sh | wc -l
```

Expected output: `11`.

- [ ] **Step 6: settings.base.json reference cleanup**

Run:
```bash
grep -c "capture-session-to-wiki\|WIKI_VAULT" claude/.claude/settings.base.json
```

Expected output: `0`.

- [ ] **Step 7: CLAUDE.md cleanup**

Run:
```bash
grep -c "Do NOT use superpowers\|Wiki capture\|no-pr-review\|/pr:create\|/pr:address\|/pr:merge" \
  claude/.claude/CLAUDE.md
```

Expected output: `0`.

- [ ] **Step 8: Commit log shape**

Run:
```bash
git log --oneline main..HEAD
```

Expected: 9 commits in this order (newest first):
```
<sha> chore(claude): drop wiki plugin and obsolete bootstrap doc
<sha> docs(claude): rewrite CLAUDE.md for superpowers-first workflow
<sha> docs(claude): rewrite superpowers-workflow.md
<sha> docs(claude): delete no-pr-review rubric
<sha> chore(claude): drop wiki capture hook and WIKI_VAULT env
<sha> docs(dotfiles): drop stale local pr plugin reference
<sha> chore(claude): swap unused plugins for compound-engineering
<sha> docs(plan): superpowers workflow reorganization implementation plan
<sha> docs(spec): superpowers workflow reorganization design
```

(9 commits = 7 reorg tasks + 1 spec commit + 1 plan commit. Task 6.5
was added during Task 1 review when an unrelated reference to
`feature-dev:code-reviewer` was found in the wiki plugin.)

- [ ] **Step 9: JSON validity**

Run:
```bash
jq empty claude/.claude/settings.base.json && echo "VALID"
```

Expected output: `VALID`.

If every verification step passes, the reorg is functionally complete
and ready for `requesting-code-review`. If any step fails, the failing
commit is the prime suspect — `git log -p <sha> -- <failing-file>` to
inspect, fix on a new commit (do not amend a published commit), re-run
the verification.

---

## Post-Plan: Next Skills

1. **`superpowers:requesting-code-review`** -- dispatch
   `superpowers:code-reviewer` against the 7-commit range; re-invoke
   after each fix batch until clean.
2. **`compound-engineering:ce-compound`** -- write
   `docs/solutions/2026-05-19-superpowers-workflow-reorg.md` capturing
   lessons from this reorg (e.g., the silently-broken WIKI_VAULT
   path; the ban-list-vs-target-workflow conflict).
3. **`superpowers:finishing-a-development-branch`** -- option 1 (local
   merge to main + push). Per CLAUDE.md (post-reorg): no-pr is default.

---

## Rollback

Each commit is independent. To revert any single change:

```bash
git revert <commit-sha>
claude-sync
```

To abandon the entire reorganization:

```bash
git checkout main
git worktree remove .claude/worktrees/superpowers-workflow-reorg
git branch -D worktree-superpowers-workflow-reorg
```

No external state changes -- fully local rollback.
