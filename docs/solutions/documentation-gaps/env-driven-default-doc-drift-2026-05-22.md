---
title: Documenting env-driven workflow defaults
date: 2026-05-22
category: documentation-gaps
module: claude
problem_type: documentation_gap
component: development_workflow
severity: medium
applies_when:
  - Behavior is controlled by an environment variable with a single hot branch
  - The unset value of that env var produces the default behavior
  - Docs label one mode as "default" without grounding it in the env-var contract
tags:
  - doc-hook-drift
  - env-driven-defaults
  - workflow-config
  - claude-hooks
related_components:
  - documentation
  - tooling
---

# Documenting env-driven workflow defaults

## Context

Four shell hooks (`git-session-start.sh`, `restore-git-context.sh`,
`worktree-exited.sh`, `git-safety.sh`) gate their no-pr behavior on
`[[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]`. Any other value (including
unset) falls through to PR-mode behavior: strict main-branch protection in
`git-safety.sh`, silent context-block injection in the other three.

The docs in `claude/.claude/CLAUDE.md` and
`claude/.claude/docs/superpowers-workflow.md` described no-pr as the
"default" workflow tail and PR mode as "opt-in." That language was inherited
from an earlier design where no-pr was treated as the everyday path. Once
the env var was added, the hook contract inverted (unset = PR mode) but the
prose stayed put. Result: a new reader following the docs would assume
no-pr was the global default even though their session's behavior was
strict PR mode.

## Guidance

When a workflow toggle is implemented as an env var with a single hot
branch (e.g., `[[ "$VAR" == "<opt-in-value>" ]]`):

1. Treat the **unset case as the default**. Docs must call it the default
   by name.
2. Document the opt-in path with the **exact env-var name, value, and
   config file** that sets it. Do not describe the opt-in path abstractly.
3. Order any "default vs opt-in" section pair with the **default first**
   in prose, matching the order in any accompanying diagram.
4. Cross-link the docs to the hook file that reads the env var so the
   contract stays grounded — when the hook semantics change, the linked
   prose is the first place to fix.

## Why This Matters

A single hot branch in the hook code creates an asymmetric contract: one
value triggers a side branch, every other value (including unset) takes
the default path. If the docs label the side branch as "default," the
reader's mental model diverges from the hook's actual behavior. The user
sees:

- "Why is `gh push origin main` blocked? Docs say no-pr is default."
- "I set up the repo per the docs but the workflow reminder never shows."

The doc/hook mismatch is silent — no error, no warning, just a slow drift
where the docs lose authority. Catching it means reading the prose with
the env-var contract in hand and asking "which value is unset?"

This pattern is broader than this one workflow. Any feature flag, mode
toggle, or capability gate implemented with a single equality check
inherits the same risk.

## When to Apply

- Adding or renaming any `CLAUDE_*`/`*_MODE`/`*_WORKFLOW` env var that
  hooks or scripts read.
- Reviewing docs that describe an "opt-in" or "default" mode without
  showing the env-var contract.
- Auditing a hooks directory for behavior that depends on env state but
  isn't surfaced in user-facing docs.

## Examples

### Before — doc describes no-pr as default; hook contract says otherwise

```bash
# claude/.claude/hooks/git-safety.sh
[[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]] && NO_PR=true
# ... NO_PR controls whether merge/push-to-main is blocked
```

```markdown
<!-- claude/.claude/CLAUDE.md (before) -->
### No-pr mode (default)

After implementation ... pick option 1 (local merge). No PR created.

### PR mode (opt-in)

When a PR is needed:
- compound-engineering:ce-commit-push-pr ...
```

A reader assumes setting nothing gives them no-pr mode. The hook actually
gives them strict PR mode (blocks push-to-main).

### After — default-first prose, env-var opt-in instruction, hook-grounded

```markdown
<!-- claude/.claude/CLAUDE.md (after) -->
### PR mode (default)

After implementation + `requesting-code-review` is clean +
`ce-compound` has documented the solution: invoke
`finishing-a-development-branch`, pick option 2 (push +
`gh pr create`). ...

### No-pr mode (opt-in)

Enable per repo by setting
`"env": {"CLAUDE_GIT_WORKFLOW": "no-pr"}` in that repo's
`.claude/settings.local.json`. The hook reads the env var; no other
config required. This dotfiles repo is the documented example.

After implementation ... pick option 1 (local merge). ...
```

The default now matches the unset hook branch. The opt-in section names
the env var, the value, and the config file. Section order in prose
mirrors the canonical workflow diagram.

## Related

- `claude/.claude/hooks/git-safety.sh` — single hot branch on
  `CLAUDE_GIT_WORKFLOW == "no-pr"` that controls main-branch protection.
- `claude/.claude/hooks/git-session-start.sh` /
  `restore-git-context.sh` / `worktree-exited.sh` — emit MODE context
  blocks only in no-pr mode; silent in default PR mode.
- `docs/solutions/workflow-issues/superpowers-workflow-reorg-2026-05-19.md`
  — prior workflow doc reorg in same `claude/.claude/docs/`.
