---
title: "Use component scopes for Superpowers spec and plan commits"
date: 2026-05-19
category: conventions
module: commit-history
problem_type: convention
component: development_workflow
severity: medium
applies_when:
  - Writing or rewriting commits for Superpowers specs and plans
  - Choosing commit scopes for files under docs/superpowers/specs or docs/superpowers/plans
  - Replaying remote commits after a local history rewrite
tags:
  - git
  - commit-scope
  - conventional-commits
  - superpowers
  - history-rewrite
---

# Use component scopes for Superpowers spec and plan commits

## Context

Superpowers brainstorming specs and writing-plans artifacts live under generic
paths:

- `docs/superpowers/specs/`
- `docs/superpowers/plans/`

Those paths describe the artifact type, not the system being changed. During
the commit-scope cleanup, history was first rewritten in the wrong direction:
Codex-focused specs and plans became subjects such as `docs(spec): ...` and
`docs(plan): ...`. The user clarified the convention: commit scope should name
the affected component from the document contents, not the artifact directory.

The same cleanup also exposed a second weak scope: `docs(dotfiles)`. In this
repo, `dotfiles` names the repository rather than a meaningful component. For
repo-wide policy docs with no concrete component, the correct subject is
unscoped `docs: ...`.

Codex session history search found no relevant prior sessions for this specific
commit-scope correction.

## Guidance

Use commit scope to identify the affected component or domain. Do not use scope
to identify the kind of file being committed.

For Superpowers specs and plans, read the document contents before choosing the
scope:

- Codex work: `docs(codex): ...`
- Claude work: `docs(claude): ...`
- read-once work: `docs(read-once): ...`
- Repo-wide policy with no concrete component: `docs: ...`

Avoid artifact-type scopes:

```text
docs(spec): design Codex workflow hardening
docs(plan): add read-once hardening implementation plan
docs(spec, plan): update workflow design and plan
```

Avoid vague repository-name scopes:

```text
docs(dotfiles): update CLAUDE instructions
```

Use concrete component scopes instead:

```text
docs(codex): design workflow hardening
docs(read-once): add hardening implementation plan
docs(claude): update agent instructions
```

Use unscoped docs commits for repo-wide policy where no component dominates:

```text
docs: design component-scoped plan spec commits
docs: plan component-scoped plan spec commits
```

When rewriting history to fix commit scopes, include remote-only commits before
pushing. In this case, the newer remote read-once branch contained:

```text
docs(plan): add read-once hardening implementation plan
```

That commit had to be replayed locally as:

```text
docs(read-once): add hardening implementation plan
```

The remote spec commit already used the component scope and did not need a
subject change:

```text
docs(read-once): add hardening design spec
```

## Why This Matters

Commit scopes are search and ownership signals. A future reader scanning
history needs to know whether a spec or plan affected Codex, Claude, read-once
hooks, or general repo policy. Scopes such as `spec` and `plan` hide that
information because they only repeat what the path already says.

Repository-name scopes have a similar problem. In a dotfiles repo, nearly every
change could be called `dotfiles`, so the scope adds little value. A concrete
component scope is better when one exists; an unscoped subject is clearer when
the change is genuinely repo-wide.

History rewrites make small convention mistakes expensive. Once a bad scope is
rewritten through local history, remote-only commits need to be reconciled too.
Use `--force-with-lease`, not a blind force push, so the push refuses to
overwrite unexpected remote movement.

## When to Apply

- A Superpowers spec or plan needs a conventional commit subject.
- A commit subject uses `docs(spec)`, `docs(plan)`, or `docs(spec, plan)`.
- A commit subject uses `docs(dotfiles)` as a generic repo-name scope.
- You are replaying remote commits after a local history rewrite.
- You are auditing commit history for component ownership.

## Examples

### Correcting local plan/spec history

Before:

```text
docs(plan): subagent approval inheritance
docs(spec): subagent approval inheritance
```

After:

```text
docs(codex): plan subagent approval inheritance
docs(codex): design subagent approval inheritance
```

### Correcting Claude instruction commits

Before:

```text
docs(dotfiles): tidy CLAUDE.md
docs(dotfiles): drop stale local pr plugin reference
```

After:

```text
docs(claude): tidy CLAUDE.md
docs(claude): drop stale local pr plugin reference
```

### Verifying the rewritten history

After rewriting, verify obsolete scopes are absent from local `HEAD`:

```bash
git log --format='%h %s' HEAD --grep='^docs(dotfiles):\|^docs(\(spec\|plan\|spec, plan\)):'
```

For Superpowers artifacts, also check the path-limited history:

```bash
git log --format='%h %s' HEAD -- docs/superpowers/specs docs/superpowers/plans \
  | rg 'docs\((spec|plan|spec, plan|dotfiles)\):'
```

Expected: no output.

When remote-only work was replayed, verify the affected tests still pass. For
the read-once branch, the verification was:

```text
claude/.claude/tests/read-once/run.sh
18 passed, 0 failed
```

Finally, publish rewritten history with a lease:

```bash
git push --force-with-lease origin main
```

In the resolved case, the remote was updated from `d64665f` to `ca2586c`.

## Related

- [Superpowers workflow reorganization](../workflow-issues/superpowers-workflow-reorg-2026-05-19.md) covers the broader Superpowers workflow that produces specs and plans.
- [Subagent-driven mechanical edit fidelity](../workflow-issues/subagent-driven-mechanical-edit-fidelity-2026-05-19.md) is related workflow guidance for executing detailed plans without drifting from the requested edit.
