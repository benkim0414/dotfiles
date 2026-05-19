---
title: "Superpowers + compound-engineering workflow reorganization"
date: "2026-05-19"
category: "workflow-issues"
module: "dotfiles/claude"
problem_type: "workflow_issue"
component: "development_workflow"
severity: "medium"
applies_when:
  - "Non-trivial features or refactors in a Claude Code project with superpowers + compound-engineering enabled"
  - "Existing CLAUDE.md forbids superpowers skills the user wants to adopt"
  - "Workflow docs reference deleted or renamed plugins, hooks, or doc files"
  - "Plugin matrix and hook context strings need to be aligned with the canonical skill chain"
related_components:
  - "tooling"
  - "documentation"
tags:
  - "superpowers"
  - "compound-engineering"
  - "claude-code"
  - "workflow"
  - "plugins"
  - "hooks"
  - "dotfiles"
---

# Superpowers + compound-engineering workflow reorganization

## Context

The previous workflow in `claude/.claude/CLAUDE.md` held a "Superpowers
integration" ban list that explicitly forbade
`subagent-driven-development`, `finishing-a-development-branch`,
`requesting-code-review`, and `receiving-code-review` -- even though
those are the canonical superpowers chain the user wanted to adopt.

The git workflow routed through a local `docs/no-pr-review.md`
two-agent rubric and `/pr:create` / `/pr:address` / `/pr:merge` slash
commands (from the `pr@skills` plugin, itself a long-extracted local
plugin). A `capture-session-to-wiki.sh` hook fired on `PreCompact` /
`SessionEnd` but `WIKI_VAULT` pointed to a Linux path
(`/home/benkim0414/workspace/wiki`) on the macOS box -- silently
failing for an unknown duration. Three plugins
(`commit-commands`, `feature-dev`, `ralph-loop`) were declared enabled
but unused under the target workflow.

## Guidance

Adopt this canonical flow for any non-trivial change in a Claude Code
project where `superpowers@superpowers-marketplace` and
`compound-engineering@compound-engineering-plugin` are both enabled
(auto memory [claude] -- feedback-plan-artifacts-in-worktree):

```
EnterWorktree                  ← hook-enforced isolation; ALL plan artifacts live here
    ↓
brainstorming                  → docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md
    ↓
writing-plans                  → docs/superpowers/plans/YYYY-MM-DD-<topic>.md
    ↓
subagent-driven-development    (TDD + systematic-debugging inline)
    ↓
verification-before-completion
    ↓
requesting-code-review         (re-invoke after each fix batch until clean)
    ↓
ce-compound                    → docs/solutions/<category>/<...>.md
    ↓
finishing-a-development-branch
   ├─ no-pr default: option 1 (local merge → push main)
   └─ PR mode:       ce-commit-push-pr + ce-resolve-pr-feedback
```

Anchor rules:

- `EnterWorktree` runs FIRST. All plan artifacts (brainstorm spec at
  `docs/superpowers/specs/`, plan at `docs/superpowers/plans/`,
  ce-compound solution doc at `docs/solutions/`) live inside the
  worktree and merge with the feature.
- Reorganize the plugin matrix to match the canonical chain. Declare
  only what the workflow actually uses; remove plugins that no longer
  fit.
- Rewrite ALL workflow-text surfaces in lockstep -- CLAUDE.md,
  `superpowers-workflow.md`, hook context strings (`MODE: no-pr`
  messages in `git-session-start.sh`, `worktree-exited.sh`,
  `restore-git-context.sh`), and any project-root README/CLAUDE.md
  references. Skipping a surface produces silent contradictions
  between what the docs say and what hooks inject at runtime.

## Why This Matters

- Aligns documented workflow with the plugins that are actually
  installed and enabled, eliminating the conflict between ban list and
  target skill chain.
- Artifacts-in-worktree rule ties design + plan + learnings to
  implementation in git history. Nothing lands on `main` until the
  feature does, and nothing gets stranded in temp dirs.
- `subagent-driven-development` runs independent tasks in parallel
  subagents with two-stage review -- faster iteration than inline
  `executing-plans` for plans with independent tasks, and the
  reviewer's clean context window catches issues an in-session
  implementer overlooks.
- `ce-compound` at the end of every feature compounds team knowledge
  into `docs/solutions/` while context is still fresh.
- Removing the silently-broken `WIKI_VAULT` / wiki capture hook
  eliminates an invisible failure mode that had been firing on every
  compaction.

## When to Apply

- Any non-trivial feature or refactor in a Claude Code project where
  `superpowers@superpowers-marketplace` and
  `compound-engineering@compound-engineering-plugin` are enabled.
- Debugging follows a parallel chain anchored on
  `systematic-debugging` instead of `brainstorming`; the rest of the
  flow (verification → review → ce-compound → finishing) still
  applies.
- Quick fixes (single-file, trivial) may skip `brainstorming` /
  `writing-plans` and treat `ce-compound` as optional, but still go
  through `EnterWorktree` → TDD → verification → review →
  finishing.

## Examples

### Before / after workflow

Before:

```
implementation → /pr:create → review via docs/no-pr-review.md two-agent loop
              → /pr:address → /pr:merge
```

`subagent-driven-development`, `finishing-a-development-branch`,
`requesting-code-review`, and `receiving-code-review` were
explicitly banned in CLAUDE.md.

After:

```
EnterWorktree → brainstorming → writing-plans
              → subagent-driven-development → verification-before-completion
              → requesting-code-review (loop) → ce-compound
              → finishing-a-development-branch (option 1 no-pr default)
```

PR mode routes through `compound-engineering:ce-commit-push-pr` +
`ce-resolve-pr-feedback`.

### Five unplanned discoveries during execution

Even with a complete spec and plan, executing the reorg surfaced five
issues the plan author hadn't anticipated. Three pattern types worth
documenting:

1. **Already-extracted local plugin** -- `claude/.claude/plugins/pr/`
   had been extracted to `benkim0414/skills` in an earlier commit
   (`58762e3`). The plan said "delete local plugin" but there was
   nothing to delete. Pivot: clean the stale doc reference in
   `dotfiles/CLAUDE.md` instead. Lesson: validate every assumed-existing
   path before writing tasks that delete or move it.

2. **Transitively stale plugin references** -- removing
   `feature-dev@claude-plugins-official` from `enabledPlugins` broke a
   reference in `claude/.claude/plugins/wiki/skills/ingest/SKILL.md`
   that named `feature-dev:code-reviewer` as a subagent type. The plan
   did not enumerate this. Pivot: drop the entire wiki plugin (Task
   6.5) since wiki capture was also being removed and the plugin had
   no other purpose. Lesson: when removing a plugin, grep every
   `*.md` and `*.sh` for the removed plugin's agent/skill names, not
   just `import`-style references.

3. **Hook context strings hold canonical workflow text** -- three
   hook scripts (`git-session-start.sh`, `worktree-exited.sh`,
   `restore-git-context.sh`) injected `MODE: no-pr` context strings
   that referenced the deleted `docs/no-pr-review.md` and the
   removed `/pr:merge` command. The plan did not enumerate these
   either. Pivot: add Task 4.5 to rewrite all five lines in lockstep
   with the doc rewrites. Lesson: hooks are part of the doc surface;
   audit them whenever workflow text changes.

4. **Orphan marketplace declarations** -- removing the last plugin
   from a local marketplace at
   `claude/.claude/plugins/.claude-plugin/marketplace.json` left a
   manifest with a dangling `./wiki` source. Caught in code-quality
   review for Task 6.5. Lesson: deleting plugins also requires
   pruning the marketplace manifests that referenced them.

5. **Stale Stow gotcha** -- the project-root `CLAUDE.md` "Stow
   gotchas" section described how to pre-create `~/.claude/plugins`
   to avoid tree-folding the local `pr` plugin -- a concern that
   evaporated when the entire `plugins/` subtree was deleted. Caught
   in the final cross-commit review. Lesson: cross-commit review at
   the end (not just per-commit) is required to catch consequences of
   the cumulative diff.

### Atomic-commit structure

The reorg landed as 14 atomic conventional commits on
`worktree-superpowers-workflow-reorg`, each independently revertable
via `git revert <sha>` + `claude-sync` (auto memory [claude] --
feedback-atomic-commits-pr):

```
33579db docs(dotfiles): drop obsolete stow gotcha for ~/.claude/plugins
38a02dd chore(claude): remove dangling benkim0414 marketplace.json
934f261 chore(claude): drop wiki plugin and obsolete bootstrap doc
bfd5f40 docs(claude): rewrite CLAUDE.md for superpowers-first workflow
54fe754 docs(claude): rewrite superpowers-workflow.md
62d2c98 chore(claude): clarify PR-mode exit message in worktree-exited.sh
0e23ff9 chore(claude): update hook MODE text for superpowers workflow
0fce1b2 docs(claude): delete no-pr-review rubric
6b44ea2 chore(claude): drop wiki capture hook and WIKI_VAULT env
bdd55ea docs(dotfiles): drop stale local pr plugin reference
6afd708 docs(spec, plan): add Task 6.5 wiki plugin + bootstrap removal
71db042 chore(claude): swap unused plugins for compound-engineering
264528e docs(plan): superpowers workflow reorganization implementation plan
f220e8b docs(spec): superpowers workflow reorganization design
```

The four extra commits beyond the 6 planned tasks (4.5, 6.5,
marketplace, stow-gotcha) all originated from review-driven iteration
-- not plan failure. Plans are starting points; review surfaces what
the plan missed.

### Process notes

- `feedback-never-assume` (auto memory [claude]) drove 4
  `AskUserQuestion` clarifications during brainstorming -- no-pr
  default, artifact placement, PR-mode handoff, ce-compound timing.
  Each clarification prevented a likely-wrong implementation choice.
- `feedback-plan-artifacts-in-worktree` (auto memory [claude]) was
  itself created during this session in response to a user correction
  to the proposed workflow ("I want every plan artifact from
  brainstorming and writing-plans to exist in the worktree"). The
  rule was saved before the spec was written so future brainstorms
  inherit it.

## Related

- [Configure Codex CLI hooks through config.base.toml](../tooling-decisions/configure-context-mode-for-codex-cli-2026-05-17.md) -- shares the "single source of truth for plugin/hook configuration" meta-pattern.
- Spec: `docs/superpowers/specs/2026-05-19-superpowers-workflow-reorg-design.md`
- Plan: `docs/superpowers/plans/2026-05-19-superpowers-workflow-reorg.md`
