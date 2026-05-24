---
title: "Mechanical edits from a detailed plan: prefer orchestrator-direct over subagent dispatch"
date: "2026-05-19"
last_updated: "2026-05-24"
category: "workflow-issues"
module: "dotfiles/claude"
problem_type: "workflow_issue"
component: "development_workflow"
severity: "medium"
applies_when:
  - "Executing a writing-plans output via subagent-driven-development in Claude Code without a standing user preference for mandatory subagent execution"
  - "A task is small and mechanical (regex tweak, single block deletion, comment update, line insertion) and the plan already contains the exact final code"
  - "The same logical file will be touched by multiple consecutive tasks"
related_components:
  - "tooling"
  - "documentation"
tags:
  - "superpowers"
  - "subagent-driven-development"
  - "writing-plans"
  - "claude-code"
  - "edit-fidelity"
---

# Mechanical edits from a detailed plan: prefer orchestrator-direct over subagent dispatch

## Context

The `superpowers:subagent-driven-development` skill prescribes a fresh subagent per plan task plus a two-stage review (spec compliance, then code quality). The intent is to preserve the orchestrator's context and isolate each task's work.

That model is the right default when a task requires creative work — designing a new file, refactoring a module, or writing non-trivial logic. It is the wrong default when a `writing-plans` task is purely mechanical and the plan already specifies the exact final code: a regex tweak, a single block deletion, a comment update, a line insertion. In those cases, the round-trip cost of an implementer dispatch plus two reviewer dispatches dwarfs the underlying edit, *and* the subagent can corrupt the file in ways the orchestrator cannot.

This learning came out of a 17-task read-once hook hardening pass where one early mechanical task (delete a five-line bypass-log rotation block) was dispatched to a subagent and returned a structurally broken hook that still passed the suite's grep-for-pattern tests.

## Guidance

When you are about to dispatch a plan task to an implementer subagent, ask three questions:

1. **Does the plan already contain the exact final code?** If yes — every step is "replace these lines with these lines" — the subagent has nothing to design.
2. **Is the touched file one the orchestrator just authored or just read?** If yes, the orchestrator already holds the maximum-fidelity context for that file.
3. **Is the edit a deletion or single-block replacement?** Subagents are most likely to drift on these, because they cannot easily verify they captured the precise line range.

If all three are "yes," do the edit directly with `Edit` / `Write` from the orchestrator. Run the test suite the plan specifies after each edit. Commit per the plan's commit message. The two-stage review pattern is preserved as a final pass over the full diff at the end of the plan, not per task.

Reserve subagents for tasks that are genuinely creative or where the plan's code is incomplete: a new hook file, a schema redesign, a non-trivial helper, or anywhere the implementer must make a design judgment.

For Codex, this historical exception does not override the standing default in
`codex/.codex/AGENTS.md`: Superpowers implementation plans use
`superpowers:subagent-driven-development` unless the user explicitly asks for
an alternative or subagents are unavailable. Treat this doc as Claude Code
incident guidance and edit-fidelity context, not as permission to bypass the
Codex subagent-driven default.

## Why This Matters

A 17-task plan with two reviews per task is ~50 subagent dispatches. Each dispatch:
- Spends time launching, reading the prompt, and emitting a report
- Re-reads files the orchestrator has already read
- Risks edit-fidelity loss when the task is mechanical

The most visible failure mode in the read-once hardening pass was a "delete this block" task that landed with the comment replacement *and* the next four lines of an unrelated `jq -cn` invocation collapsed into the same edit. The hook silently lost its bypass-log writer:

```bash
    # Before
    _log_file="${_log_dir}/read-once-bypass-${_log_date}.log"
    if [[ -f "$_log_file" ]]; then
      _sz=$(stat -c %s "$_log_file" 2>/dev/null || stat -f %z "$_log_file" 2>/dev/null || echo 0)
      if (( _sz > 52428800 )); then
        mv "$_log_file" "${_log_file}.1" 2>/dev/null || true
      fi
    fi
    jq -cn \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
      --arg sid "$SESSION_ID" \

    # After (broken)
    _log_file="${_log_dir}/read-once-bypass-${_log_date}.log"
    # Filename is date-stamped, so rotation happens implicitly per day.      --arg sid "$SESSION_ID" \
      --arg tool "$TOOL_NAME" \
```

The comment replaced not just the `if [[ -f ]]; ...; fi` block but also `_log_date`, the `_log_file` re-assignment, *and* the `jq -cn \` line and the `--arg ts` line — and concatenated the new comment onto `--arg sid`. The result was syntactically valid (no parse error) but functionally dead: `jq` is never called, so no bypass entry is ever written.

The bug was not caught by:
- The implementer's self-review (the report claimed success)
- The shell test suite (the test grepped for the `mv` pattern, which was indeed gone)
- The spec-compliance reviewer (the diff matched the spec's intent at a verbal level)

It was caught by the code-quality reviewer on a careful read of the actual diff. The recovery required `git reset --hard` and a manual orchestrator-side redo.

The cost was: one wasted implementer dispatch, one wasted spec review, one wasted code-quality review, plus the reset and redo. Net wall time: roughly five times longer than doing the edit directly would have been. Net token spend: substantially worse.

## When to Apply

- Plan tasks whose every step says "replace these lines with these lines" or "delete this block" or "add this comment"
- Tasks where the orchestrator just wrote or just read the file being modified
- Sequences of mechanical edits to the same file (batch them inline rather than re-dispatching per task)
- Recovery from a subagent-induced corruption: prefer orchestrator-direct redo over another subagent round

Do **not** apply this shortcut to:
- New file authoring that involves design (schemas, hooks, helpers, library modules)
- Refactors that require holding multiple related files in mind
- Anywhere the plan says "implement X" without giving the final code

## Examples

**Before — subagent for a 5-line deletion:**

```text
Agent(model: haiku) → "Delete the rotation block in read-once.sh per Task 3 of the plan"
  → implementer dispatch (read file, infer line range, attempt edit, run tests, commit)
  → spec review (read commit, compare to plan)
  → code review (read commit, assess quality)
  → orchestrator marks task complete
  Wall time: ~3-5 minutes per task. Drift risk: real.
```

**After — orchestrator does it:**

```text
Edit(file_path, old_string=<exact 5-line block>, new_string="    # rotation happens implicitly per day.")
Bash("bash run.sh && git add ... && git commit -m '...'")
  Wall time: ~30 seconds. Drift risk: nil (Edit requires byte-exact old_string match).
```

The `Edit` tool's exact-match requirement is the key safety mechanism: an orchestrator that holds the file's exact content in context can guarantee the old_string is unambiguous, which the implementer subagent — working from a fresh read of a freshly-pulled version — cannot.

## Related

- `docs/solutions/conventions/default-subagent-driven-superpowers-execution.md` -- current Codex convention that preselects `superpowers:subagent-driven-development` for Superpowers implementation plans.

- [Superpowers + compound-engineering workflow reorganization](../workflow-issues/superpowers-workflow-reorg-2026-05-19.md) — same plugin matrix and skill chain that defines `subagent-driven-development`
- `~/.claude/docs/superpowers-workflow.md` — canonical skill chain that this learning amends
- `~/.claude/CLAUDE.md` — the global instruction file that prescribes subagent-driven-development as the default executor
