# ce-compound auto-pick recommended options

**Date:** 2026-06-16
**Status:** Approved

## Problem

Every `compound-engineering:ce-compound` run stops on interactive blocking
prompts -- Full vs Lightweight, then session-history yes/no, plus a
Discoverability Check consent and a closing "What's next?" menu. The user
always wants the recommended option, so the prompts are pure friction. This
mirrors the already-solved `writing-plans` "Which approach?" handoff, which a
CLAUDE.md directive auto-resolves.

## Goal

Add a CLAUDE.md directive instructing Claude to auto-select the recommended
option for every ce-compound interactive prompt, announce the choice in one
line, and proceed -- without asking. User instructions override skill behavior
(superpowers instruction-priority rule), so the skill file itself is not
touched.

## Scope

- One edit: `claude/.claude/CLAUDE.md` (stowed to `~/.claude/CLAUDE.md`).
- New subsection `### Execution handoff for ce-compound`, placed immediately
  after the `### Execution handoff after writing-plans` subsection and before
  `### Commit rules`.
- No change to the ce-compound skill (plugin cache, not ours to edit).
- Interactive mode only -- headless mode already skips every prompt.

## Design

Directive text to add:

```markdown
### Execution handoff for `ce-compound`

When `compound-engineering:ce-compound` reaches any interactive blocking
prompt, do NOT ask. Auto-select the recommended option, announce the choice
in one line, then proceed. Mirrors the `writing-plans` handoff above.
(Headless mode already skips these prompts -- this covers interactive runs.)

Prompt-by-prompt:

1. **Full vs Lightweight** -> always **Full**, the option the skill marks
   `(recommended)`.
2. **Session history** (Full only) -> the skill marks no recommendation, so
   pick per-run and state which. Default to **skipping** (the skill flags
   added time + token cost); opt in only when the documented problem clearly
   spans multiple prior sessions and that history would materially improve
   the doc.
3. **Discoverability Check consent** -> if the check finds a gap, apply the
   smallest fitting edit directly; if not, move on. No prompt either way.
4. **"What's next?" menu** -> auto-pick **only in no-pr repos**. Detect mode
   from the git-workflow session context / `CLAUDE_GIT_WORKFLOW=no-pr`.
   - **no-pr mode**: pick option 1 **Continue workflow** (skill-marked
     `(recommended)`) -> proceed to `finishing-a-development-branch`
     option 1 (local merge).
   - **PR mode (default)**: present the menu normally -- do NOT auto-select.
     Pushing + opening a PR is outward-facing; the user controls that step.

Announce in one line, e.g. `Auto-running ce-compound Full, skipping session
history, applying discoverability edit, continuing workflow per user
preference.` (drop the "continuing workflow" clause in PR-mode repos).

Override: if the user names a different choice in the same turn (e.g. "use
lightweight", "search session history", "stop after the doc"), honour that
instead.
```

## Decisions

- **Session history** stays Claude's per-run judgment (user's "LLM-recommended"
  answer) with a documented lean toward skipping, so behavior is not silently
  nondeterministic.
- **Discoverability** auto-applies the edit because that is the skill's
  recommended action when a gap exists.
- **"What's next?"** auto-pick is gated on no-pr mode. PR-mode runs keep the
  menu because the recommended next step (push + PR) is outward-facing.

## Verification

- `claude-sync` regenerates `~/.claude/settings.json` (unaffected -- CLAUDE.md
  is stowed directly, not generated). Confirm the symlink resolves and the new
  subsection renders.
- Manual: next interactive ce-compound run auto-selects without prompting and
  prints the announce line.
