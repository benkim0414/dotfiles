# Superpowers workflow integration

Skills auto-trigger by context (model-invoked). Explicit invocation:
`/superpowers:<skill-name>`.

The six adopted skills slot into two primary workflows below.
For skills that conflict with existing tooling, see CLAUDE.md § Superpowers integration.

---

## Feature development

```
brainstorming          ← design / requirements phase (before any code)
    ↓
plan mode              ← implementation approval (EnterPlanMode → ExitPlanMode)
    ↓
EnterWorktree          ← isolation (hook-enforced)
    ↓
writing-plans          ← step-by-step breakdown from the approved plan
    ↓
test-driven-development← write failing tests before implementation
    ↓
executing-plans        ← implement in batches with human checkpoints
    ↓
verification-before-completion ← confirm all claims before reporting done
    ↓
no-pr-review.md loop   ← two-agent review (see ~/.claude/docs/no-pr-review.md)
    ↓
ExitWorktree → merge → push
```

### When each skill fires

| Skill | Auto-triggers when |
|---|---|
| `brainstorming` | Asked to create/design something new |
| `writing-plans` | Have a spec/requirements for multi-step work |
| `test-driven-development` | About to implement a feature or bugfix |
| `executing-plans` | Have a written plan to execute |
| `systematic-debugging` | Investigating a bug, test failure, or unexpected behavior |
| `verification-before-completion` | About to claim something is done/fixed |

---

## Debugging

```
systematic-debugging   ← any bug, test failure, or unexpected behavior
    ↓
EnterWorktree          ← isolation for the fix
    ↓
test-driven-development← add a failing test that reproduces the bug
    ↓
fix implementation
    ↓
verification-before-completion
    ↓
no-pr-review.md loop
    ↓
ExitWorktree → merge → push
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
verification-before-completion → no-pr-review.md → merge
```

Skip `brainstorming` and `writing-plans` for single-file or trivial fixes.

---

## Notes

- `brainstorming` is Socratic — it asks questions to refine the design before
  committing to an approach. Let it run before opening a worktree.
- `executing-plans` runs in batches and pauses for human checkpoints; do not
  skip checkpoints to speed up — they are the safety valve.
- `verification-before-completion` is a pre-report gate, not a post-merge check.
  Run it before saying "done" or "fixed", not after.
- Plan mode and `writing-plans` are different granularities: plan mode approves
  the high-level approach before the worktree opens; `writing-plans` produces
  the step-by-step breakdown inside the worktree.
