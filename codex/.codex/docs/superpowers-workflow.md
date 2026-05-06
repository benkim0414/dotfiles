# Codex Superpowers workflow

Superpowers is installed as `superpowers@superpowers-marketplace`. Use it to
add planning, TDD, debugging, and verification discipline to the existing Codex
workflow. Do not let it replace local git, review, or safety policy.

## Core rule

The repo workflow wins when it conflicts with Superpowers guidance:

- Work happens in isolated git worktrees.
- Commits are atomic and use selective staging.
- No-PR mode uses `~/.codex/docs/no-pr-review.md` before merging.
- Codex hooks and `AGENTS.md` are the authority for safety boundaries.

Superpowers improves the work inside those boundaries.

## Skill map

Use these skills directly by name when they fit the task:

| Skill | Use it when | Default action |
| --- | --- |
| `superpowers:brainstorming` | The request is creative, ambiguous, or needs product/design refinement before code. | Use before opening a worktree when intent is still fluid. |
| `superpowers:writing-plans` | Requirements are clear enough to turn into an implementation plan. | Use for non-trivial changes that need a handoff-quality plan. |
| `superpowers:test-driven-development` | Implementing a feature or bugfix where a focused test can lead the change. | Use when the repo has a practical test seam for the behavior. |
| `superpowers:systematic-debugging` | A bug, test failure, warning, or unexpected behavior needs root-cause work. | Use before editing so the fix follows evidence, not symptoms. |
| `superpowers:executing-plans` | A written plan exists and checkpointed batch execution is useful. | Use as a checklist, but keep Codex worktree and review policy in charge. |
| `superpowers:requesting-code-review` | A major task, plan checkpoint, or pre-merge review needs fresh eyes. | Borrow its reviewer prompt shape inside `docs/no-pr-review.md`. |
| `superpowers:receiving-code-review` | Review feedback must be triaged before fixes. | Verify each finding against the codebase before changing code. |
| `superpowers:verification-before-completion` | You are about to say the work is done, fixed, passing, or ready to merge. | Run fresh checks, read the output, then make only evidence-backed claims. |

Skip Superpowers for trivial read-only questions, tiny mechanical edits, or
tasks where the next correct step is already obvious from repo instructions.

Borrow concepts only from these skills unless the user explicitly asks for the
Superpowers flow:

| Skill | Why it is not the source of truth |
| --- | --- |
| `superpowers:using-git-worktrees` | `AGENTS.md` defines this repo's worktree layout and branch creation command. |
| `superpowers:finishing-a-development-branch` | This repo defaults to no-PR merge after the local review loop, not an open-ended finish menu. |
| `superpowers:subagent-driven-development` | Codex delegation is controlled by active instructions and should stay bounded and explicit. |

## Do not delegate these decisions to Superpowers

- **Worktree creation:** follow `AGENTS.md`: `git worktree add
  ../<branch-name> -b <branch-name>`, then run edits from that worktree. Do not
  use `superpowers:using-git-worktrees` as the source of truth.
- **Branch finishing:** use the local no-PR flow: commit in the worktree, run
  `~/.codex/docs/no-pr-review.md`, merge from the main worktree, then push.
  Do not replace this with `superpowers:finishing-a-development-branch`; only
  borrow its safety checks for pre-merge verification, post-merge verification,
  and cleanup after success.
- **Code review:** prefer Codex `reviewer` agents and the no-PR review loop.
  Use Superpowers review skills as prompt/checklist material only when they fit
  `docs/no-pr-review.md`.
- **Skill authoring:** use Codex `skill-creator`, not
  `superpowers:writing-skills`, unless the task is specifically about
  Superpowers skill style.
- **Always-on behavior:** do not treat `superpowers:using-superpowers` as a
  session-start requirement. Use this guide and `AGENTS.md` as the standing
  instructions; invoke individual Superpowers skills only when they fit the
  task.
- **Parallel delegation:** use `superpowers:dispatching-parallel-agents` only
  when active Codex instructions allow spawned agents and the work can be split
  into bounded, independent tasks.

## Feature workflow

Use this for new behavior, non-trivial refactors, or design-heavy changes:

```text
superpowers:brainstorming
  -> high-level plan or user-approved direction
  -> create isolated worktree
  -> superpowers:writing-plans
  -> superpowers:test-driven-development
  -> implement in focused commits
  -> superpowers:verification-before-completion
  -> no-pr-review.md loop
  -> merge main with a merge commit
```

Notes:

- Run `brainstorming` before opening a worktree when the design is still fluid.
- Run `writing-plans` after the approach is stable enough to implement.
- Keep commits aligned to logical changes, even if `executing-plans` groups work
  into larger batches.

## Debugging workflow

Use this for failures, warnings, regressions, and unexpected behavior:

```text
superpowers:systematic-debugging
  -> reproduce and isolate
  -> create isolated worktree for the fix
  -> superpowers:test-driven-development
  -> fix root cause
  -> superpowers:verification-before-completion
  -> no-pr-review.md loop
  -> merge main with a merge commit
```

The debugging skill should drive root-cause analysis. Avoid patches based only
on the first plausible symptom.

## Small fix workflow

Use this when the change is narrow and the expected fix is already clear:

```text
create isolated worktree
  -> focused test, lint, or inspection
  -> edit
  -> superpowers:verification-before-completion
  -> atomic commit
  -> no-pr-review.md loop if tracked files changed
```

Skip `brainstorming` and `writing-plans` here unless the "small" fix turns out
to be ambiguous.

## Codex tool mapping

Superpowers skills may mention Claude tool names. Use Codex equivalents:

| Skill wording | Codex equivalent |
| --- | --- |
| `Task` | `spawn_agent` |
| Multiple `Task` calls | Multiple bounded `spawn_agent` calls with disjoint responsibilities |
| Task result | `wait_agent` |
| Task cleanup | `close_agent` |
| `TodoWrite` | `update_plan` |
| `Read`, `Write`, `Edit`, `Bash` | Native Codex tools |

Only spawn agents when the active Codex instructions allow delegation. Keep
local workflow policy in the main rollout.

## Codex adaptation rules

- Local repo policy wins over skill text, especially for git, staging, branch
  cleanup, and review gates.
- When a Superpowers skill says to dispatch review, use Codex `reviewer` agents
  only if delegation is allowed and the prompt is bounded to the branch diff.
- When a Superpowers skill says to finish a branch, continue with
  `docs/no-pr-review.md` instead of presenting merge/PR/keep/discard choices.
- When Superpowers guidance conflicts with a user preference, active developer
  instruction, or hook policy, follow the stricter local rule and note the
  adaptation in the final response.

## Verification gate

Before saying work is complete:

1. Run the relevant checks for the touched area.
2. Inspect the diff for workflow violations and doc drift.
3. Use `superpowers:verification-before-completion` if any success claim will
   depend on test, lint, build, or review output.
4. Report what changed, what was checked, and anything not verified.
