# Superpowers Spec Recap Workflow Design

## Goal

Codex should summarize the design spec at the end of every
`superpowers:brainstorming` workflow. The user wants a concise recap before the
written-spec review gate so obvious or straightforward specs can be reviewed
without reading the full `*-design.md` file every time.

The recap supplements the committed spec. It does not remove the normal
brainstorming requirement to write a spec, self-review it, and wait for user
approval before moving to `superpowers:writing-plans`.

## Recommended Approach

Record the behavior as a durable Codex workflow rule in
`codex/.codex/AGENTS.md`. That file is user-owned, version-controlled, and
higher priority than third-party plugin skill text. It also matches the existing
repo convention for personal Superpowers workflow defaults such as defaulting
implementation-plan execution to `superpowers:subagent-driven-development`.

Also update the local Superpowers workflow documentation so the expected handoff
is visible when reading the repo docs. The enforcement point remains
`AGENTS.md`; the workflow doc is explanatory.

Avoid patching the cached Superpowers plugin skill. Cached plugin files can be
overwritten by plugin updates and would create a hidden local fork of upstream
skill behavior.

## Workflow

After `superpowers:brainstorming` writes and self-reviews a design spec, Codex
must include a concise structured recap in the user-facing review message.

The recap should include:

- Spec path.
- Goal or user problem.
- Recommended approach.
- Key design decisions.
- Implementation boundaries or out-of-scope items.
- Main risks, validation points, or tests.

The message should still ask the user to review and approve before planning.
The user may approve from the summary, open the full spec, or request changes.
Codex must not invoke `superpowers:writing-plans` until the user approves the
written spec review gate.

## Instruction Changes

Add a new `Superpowers Spec Review Workflow` section to
`codex/.codex/AGENTS.md` with these rules:

- After a Superpowers brainstorming spec is written and self-reviewed, summarize
  the spec before asking for user review.
- Keep the summary concise and structured around the goal, approach, key
  decisions, boundaries, risks or tests, and spec path.
- The summary is a review aid, not a replacement for the committed spec.
- Preserve the normal approval gate before `superpowers:writing-plans`.
- Apply the rule even when the design seems obvious.

Update `claude/.claude/docs/superpowers-workflow.md` in the brainstorming
portion of the feature-development workflow to mention that the spec review
handoff includes a recap.

## Testing and Verification

This is a documentation and instruction change. Verification should include:

- Inspect the final diff to confirm the durable instruction is in
  `codex/.codex/AGENTS.md`.
- Confirm the workflow doc describes the same recap handoff without weakening
  the brainstorming review gate.
- Run a text search for the new section heading and key phrase so future agents
  can find the rule.

No runtime test is expected because the change affects agent instructions and
workflow documentation, not executable code.
