---
title: "Encode recurring workflow preferences via CLAUDE.md directives plus auto-memory, not via skill-file edits"
date: "2026-05-26"
last_updated: "2026-05-26"
category: "workflow-issues"
module: "dotfiles/claude"
problem_type: "workflow_issue"
component: "development_workflow"
severity: "low"
applies_when:
  - "A plugin-provided skill repeatedly prompts the user for a choice the user always answers the same way"
  - "The preference must persist across plugin upgrades that overwrite the cached skill file"
  - "The behaviour change is conditional and cannot be expressed as a static settings.json permission rule"
related_components:
  - "tooling"
  - "documentation"
tags:
  - "claude-md"
  - "auto-memory"
  - "writing-plans"
  - "subagent-driven-development"
  - "superpowers"
  - "workflow-preference"
  - "plugin-upgrade-safety"
---

# Encode recurring workflow preferences via CLAUDE.md directives plus auto-memory, not via skill-file edits

## Context

Plugin-provided skills frequently end with binary-choice prompts that
the user answers the same way every session. Concrete example from
this repo on 2026-05-26: `superpowers:writing-plans` finishes by
asking "Which approach? 1. Subagent-Driven (recommended) 2. Inline
Execution". The user picks option 1 in every prior session, so the
prompt is friction without decision value.

The naive fix — editing the skill file at
`~/.claude/plugins/cache/superpowers-marketplace/superpowers/<version>/skills/writing-plans/SKILL.md`
to remove the prompt — is fragile. The cached skill is overwritten on
every plugin upgrade, so the edit silently disappears. Worse, the
disappearance is invisible: the prompt simply returns without warning,
and the user re-discovers the friction.

The same anti-pattern shows up whenever someone wants to suppress,
shortcut, or auto-answer a recurring skill prompt.

## Guidance

Encode the preference in two durable artefacts, both outside the
plugin cache:

1. **Add a directive paragraph to `~/.claude/CLAUDE.md`** (in this
   repo, the stowed source is `claude/.claude/CLAUDE.md`). Place it
   inside the section that documents the relevant workflow chain so
   the directive sits next to the context it modifies. Phrase the
   directive so it tracks the skill's recommendation rather than
   hard-coding a specific skill name, and always keep a stated
   override path.

   Example pattern (from this repo, broadened in commit `a275ccb`
   after the initial `d85353f` shipped a narrower form):

   ```markdown
   ### Execution handoff after `writing-plans`

   When `superpowers:writing-plans` finishes saving the plan and
   reaches its "Execution Handoff" section, do NOT prompt the user
   with the "Which approach?" question. Pick the most appropriate
   execution path yourself and announce the choice in one line,
   then proceed.

   Decision rule:

   1. Default: superpowers:subagent-driven-development (the
      skill's recommended option).
   2. Exception — orchestrator-direct: when the plan contains the
      exact final code and tasks are mechanical edits, execute
      inline from the orchestrator without dispatching subagents
      (per feedback_subagent_mechanical_edits).
   3. Exception — superpowers:executing-plans: if you would
      otherwise have judged inline batch execution a better fit.

   Override: explicit user request for a different path in the
   same turn still wins.
   ```

   Two recognition cues — the section name and the prompt text —
   give the directive resilience to single-anchor renames upstream.
   A three-path decision rule (default / orchestrator-direct /
   executing-plans) covers all execution shapes Claude would
   reasonably choose, not just the two listed in the skill's prompt.
   This avoids the false dichotomy of "subagent-driven vs
   executing-plans" silently forcing subagent dispatch on a
   mechanical-edit plan that should bypass dispatch entirely.

2. **Write a matching `feedback`-typed auto-memory file** under
   `~/.claude/projects/<sanitised-project-path>/memory/` and add a
   one-line entry to that directory's `MEMORY.md` index. Follow the
   global memory rules (`name`, `description`, `metadata.type:
   feedback`, then **Why:** and **How to apply:** lines). Cross-link
   to related feedback files with `[[name]]` wikilinks.

   Memory files live outside the dotfiles repo's working tree, so
   they are runtime artefacts — not committed. The harness manages
   them; treat the writes as side effects of the implementation
   commit, not as additional commits.

Do not edit the skill file itself. Skill-file edits are clobbered on
plugin upgrade; CLAUDE.md and the auto-memory store survive.

## Why This Matters

CLAUDE.md is loaded into every session's system prompt, so the
directive is read on every turn. The auto-memory index (`MEMORY.md`)
is also injected at session start. Together they give the preference
two reinforcing channels. Plugin upgrades touch neither.

Editing the cached skill file fails on three counts. (a) The edit
disappears on the next plugin update. (b) The user has no signal that
it disappeared until the prompt returns. (c) Anyone else inheriting
the workflow (a colleague, a fresh machine) does not get the
behaviour unless they replay the same hand-edit. The CLAUDE.md +
auto-memory approach travels with the dotfiles repo and the per-
project memory store, so the preference reproduces wherever those
travel.

Tracking "whichever option the skill marks as recommended" rather
than the literal skill name is a small extra hedge: it means the
directive does not need a follow-up edit if the upstream skill
swaps which option carries the `(recommended)` label.

Equally important: the directive must not silently force one of the
two options the skill prompts about. Other auto-memory entries (in
this repo, `feedback_subagent_mechanical_edits`) can authorise a
third path — orchestrator-direct — that the skill prompt never
mentions. A "pick the most appropriate execution path" framing
delegates the choice to existing judgment rules without re-litigating
each prompt; a narrow "default to subagent-driven" framing would
override those rules and revert mechanical edits to slower subagent
dispatch.

## When to Apply

- A skill prompt asks the same multi-choice question every session
  and the user has answered it the same way at least twice with no
  evidence the answer would ever change in this repo's context.
- The desired behaviour change is conditional on a specific skill
  state (finished saving the plan, opened a worktree, etc.) and
  cannot be expressed by a static `permissions.allow` or
  `permissions.deny` rule in `settings.json`.
- The behaviour must persist across plugin upgrades and across the
  user's other machines that stow the same dotfiles.

Do **not** apply this pattern for:

- One-off in-session overrides (just answer the prompt).
- Behaviour that the harness already lets you configure declaratively
  (use the declarative path — hooks, permissions, env vars).
- Anything that hides risk from the user (e.g., suppressing a
  destructive-action confirmation). Keep CLAUDE.md directives
  scoped to friction reduction, not safety bypasses.

## Examples

**Before (skill-edit anti-pattern, fragile):**

```bash
# DON'T DO THIS — the edit is overwritten on every plugin upgrade
$EDITOR ~/.claude/plugins/cache/superpowers-marketplace/superpowers/5.0.7/skills/writing-plans/SKILL.md
# Delete the "Execution Handoff" prompt block.
# Save. Hope the next plugin update does not exist.
```

**After (durable directive + auto-memory):**

1. In the dotfiles repo, edit `claude/.claude/CLAUDE.md`. Insert the
   directive paragraph next to the workflow chain it modifies.

2. Write the auto-memory feedback file via the standard memory
   workflow:

   ```markdown
   ---
   name: writing-plans-auto-subagent
   description: Auto-invoke the writing-plans recommended execution skill without prompting
   metadata:
     type: feedback
   ---

   After `superpowers:writing-plans` ... (full text mirrors the
   CLAUDE.md directive plus a **Why:** and **How to apply:** line).
   ```

3. Append the one-line index entry to the project's
   `memory/MEMORY.md`.

This repo's implementation lives on the `main` branch as of
2026-05-26. See:

- `claude/.claude/CLAUDE.md` — directive under `### Execution handoff
  after `writing-plans``.
- `~/.claude/projects/-Users-ben-workspace-dotfiles/memory/feedback_writing_plans_auto_subagent.md`
  — runtime memory file.
- `docs/superpowers/specs/2026-05-26-writing-plans-auto-subagent-design.md`
  — original spec.
- `docs/superpowers/plans/2026-05-26-writing-plans-auto-subagent.md`
  — implementation plan.

## Related

- `docs/solutions/workflow-issues/subagent-driven-mechanical-edit-fidelity-2026-05-19.md`
  — sibling preference (mechanical edits skip subagent dispatch);
  same encoding pattern (CLAUDE.md + auto-memory) applied to a
  different recurring choice.
- `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`
  — example of choosing the durable workaround over the fragile one
  in a different domain (MCP wrapper rollback).
