# Auto-invoke recommended execution skill after writing-plans

**Date:** 2026-05-26
**Status:** Approved

## Problem

After `superpowers:writing-plans` finishes drafting a plan, its
"Execution Handoff" section prompts the user with two options:

1. Subagent-Driven (recommended) — invokes
   `superpowers:subagent-driven-development`
2. Inline Execution — invokes `superpowers:executing-plans`

The user has answered "1" every time. The prompt adds friction
without adding decision value, because the recommendation has been
correct in every prior session.

## Goal

Skip the "Which approach?" prompt and auto-invoke whichever option
`writing-plans` marks as recommended (today: subagent-driven-
development). The directive must:

- Survive plugin upgrades that overwrite the cached skill file.
- Track the recommendation rather than hard-coding the skill name,
  so future plugin updates that change the recommended option do not
  require another rewrite of the user instruction.
- Allow the user to override per session by explicitly asking for
  inline execution.

## Out of scope

- Editing the cached skill file under
  `~/.claude/plugins/cache/superpowers-marketplace/superpowers/<ver>/skills/writing-plans/SKILL.md`.
  Fragile, lost on upgrade.
- Changing other Execution Handoff / option prompts in the workflow
  (`brainstorming` → `writing-plans`, `finishing-a-development-branch`
  options 1-4). Those still prompt as written.
- Changing the recommendation itself. This only changes how the
  existing recommendation is acted on.

## Design

Two artefacts, written and committed in the worktree:

### 1. `claude/.claude/CLAUDE.md` (canonical workflow section)

Add a short note under the canonical workflow block telling Claude
that after `writing-plans` saves the plan, the recommended execution
skill is invoked directly without prompting.

The note references "whichever execution skill `writing-plans` marks
as recommended (today: `superpowers:subagent-driven-development`)" so
the directive remains correct if the recommended option changes
upstream.

The note must also state the user override path: an explicit user
request for inline execution / `executing-plans` still wins.

Location inside CLAUDE.md: inside the "## Git Workflow" → "Canonical
workflow" subsection, immediately after the workflow diagram block,
because that is where the chain `writing-plans →
subagent-driven-development` is documented. Adjacent context makes
the directive easy to find when reading the workflow end-to-end.

### 2. Auto-memory feedback file

New file:
`/Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/feedback_writing_plans_auto_subagent.md`

Frontmatter `type: feedback`. Body structured per global memory rules:

- Rule: after `writing-plans` Execution Handoff, auto-invoke the
  recommended execution skill without prompting.
- **Why:** user has always picked option 1 (recommended); the prompt
  is friction, not a decision.
- **How to apply:** when `writing-plans` finishes saving the plan,
  state the choice in one line ("Auto-invoking
  `subagent-driven-development` per user preference") and proceed.
  Skip the multiple-choice question. If the user explicitly asks for
  inline execution / `executing-plans`, honour that instead.

Index entry in
`/Users/ben/.claude/projects/-Users-ben-workspace-dotfiles/memory/MEMORY.md`
referencing the new file.

## Architecture / interaction

```
writing-plans
    ↓ (plan saved)
    ↓ Execution Handoff section reached
    ↓
    CLAUDE.md directive + feedback memory detected
    ↓
    Auto-invoke superpowers:subagent-driven-development
    ↓
    (user can interrupt with explicit "use executing-plans" override)
```

No code changes to the skill file. No hook required — the directive
is read every session as part of `~/.claude/CLAUDE.md` and the auto-
memory index, both already loaded into the system prompt.

## Testing / verification

Behavioural, not automated. Verification steps:

1. After spec + plan + implementation merge, start a fresh session.
2. Run a brainstorm → writing-plans flow on any small change.
3. Confirm `writing-plans` finishes the plan, states the auto-
   invocation in one line, and proceeds into
   `subagent-driven-development` without showing the "Which
   approach?" prompt.
4. Confirm an explicit user override ("use executing-plans instead")
   in a separate session is honoured.

## Risks

- Future plugin update changes the recommendation phrasing. The
  directive references "whichever option `writing-plans` marks as
  recommended", so the wording is robust to renaming. If the entire
  Execution Handoff section is removed, the directive becomes a
  no-op (harmless).
- User changes their mind about wanting the prompt. Remove the
  CLAUDE.md note and the feedback memory file; behaviour reverts.

## Post-design scope expansion (2026-05-26)

After the initial design landed, the user pointed out a case the
narrow directive failed to cover: plans that should be executed
orchestrator-direct per the existing
`feedback_subagent_mechanical_edits` auto-memory, rather than via
`subagent-driven-development` or `executing-plans`. A directive that
"auto-invokes whichever option the skill marks as recommended"
silently forces one of the two options the skill prompts about and
overrides the mechanical-edits memory.

The directive was broadened to a three-path decision rule:

1. Default — `superpowers:subagent-driven-development` (skill's
   recommended option).
2. Exception — orchestrator-direct, when the plan contains the exact
   final code and tasks are mechanical edits (mirrors
   `feedback_subagent_mechanical_edits`).
3. Exception — `superpowers:executing-plans`, when inline batch
   execution is the better fit (e.g., tightly-coupled tasks).

User-override behaviour is unchanged. Live in CLAUDE.md commit
`a275ccb`, memory file rewrite of the same date, and the
`docs/solutions/workflow-issues/encode-workflow-preferences-via-claude-md-2026-05-26.md`
learning doc.
