# Component-Scoped Plan and Spec Commits

**Status:** Approved design, pending implementation plan
**Date:** 2026-05-19

## Problem

Superpowers brainstorming specs and writing-plans artifacts live under generic
paths:

- `docs/superpowers/specs/`
- `docs/superpowers/plans/`

Recent history briefly used commit scopes such as `docs(spec)` and
`docs(plan)` for those files. That makes the artifact type visible, but hides
the subsystem the work actually changes. A future reader scanning history by
component cannot tell whether a plan/spec belongs to Codex, Claude, dotfiles,
or another subsystem without opening the commit.

The repository already treats commit scope as component ownership for normal
implementation commits, for example `fix(codex)` and `docs(claude)`. Plan and
spec commits should follow the same rule. If a change is repo-wide and does not
belong to a specific component, omit the scope instead of inventing a generic
repo scope.

## Decision

Use the affected component as the commit scope for plan and spec commits.

The file path identifies the artifact type. The commit subject should identify
the subsystem and use the subject text to preserve whether the commit is a
design or plan artifact.

Examples:

- `docs(codex): design subagent approval inheritance`
- `docs(codex): plan subagent approval inheritance`
- `docs(claude): design superpowers workflow reorganization`
- `docs(claude): plan superpowers workflow reorganization`
- `docs: design component-scoped plan spec commits`

Avoid `docs(spec)` and `docs(plan)` because those scopes describe document
shape, not ownership.

## Scope Inference

When committing a Superpowers spec or plan, infer scope from the document's
contents and intended implementation target, not from its directory.

Rules:

1. If the spec or plan changes Codex behavior, configuration, hooks, skills, or
   instructions, use `codex`.
2. If it changes Claude behavior, configuration, hooks, plugins, or
   instructions, use `claude`.
3. If it changes repository-level policy, shared dotfiles structure, or cuts
   across multiple components without one dominant target, omit the scope and
   use an unscoped subject such as `docs: ...`.
4. If a future component has an established scope in recent history, use that
   component scope.
5. If a document intentionally covers multiple components and one component is
   clearly dominant, use the dominant component. If no component dominates, omit
   the scope.

## History Correction

The current local history should be rewritten so reachable plan/spec commits
that were changed to `docs(spec)`, `docs(plan)`, or `docs(spec, plan)` regain
component scopes based on their contents.

Expected corrections include:

- Codex-focused plans/specs become `docs(codex): design ...` or
  `docs(codex): plan ...`.
- Claude-focused workflow reorganization plans/specs become `docs(claude): ...`.
- Repository-wide policy plans/specs become unscoped `docs: ...`.

The rewrite must change only commit messages. The final tree should remain
unchanged compared with the current local branch before the rewrite.

## Verification

Verification should prove both message policy and content preservation:

1. `git log --format='%h %s' -- docs/superpowers/specs docs/superpowers/plans`
   shows component scopes rather than artifact scopes.
2. No reachable commit subject remains with `docs(spec)`, `docs(plan)`, or
   `docs(spec, plan)`.
3. The final tree diff against the pre-rewrite branch tip is empty.
4. Existing unrelated untracked plan files remain untouched.

## Out of Scope

- Changing the directory layout for specs or plans.
- Adding a commit-msg hook for scope enforcement.
- Rewriting already-published remote history beyond the local branch work the
  user explicitly requested.
- Changing implementation commits that already use correct component scopes.
