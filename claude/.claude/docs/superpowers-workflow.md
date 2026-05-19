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
