---
title: "Use content-derived scopes for generated documentation commits"
date: 2026-05-19
last_updated: 2026-05-19
category: conventions
module: commit-history
problem_type: convention
component: development_workflow
severity: medium
applies_when:
  - Writing or rewriting commits for generated or planning documentation
  - Choosing commit scopes for docs whose path names the artifact type rather than the affected component
  - Maintaining user-level Codex commit guidance that applies across projects
  - Replaying remote commits after a local history rewrite
tags:
  - git
  - commit-scope
  - conventional-commits
  - generated-docs
  - codex
  - history-rewrite
---

# Use content-derived scopes for generated documentation commits

## Context

Generated and planning documentation often lives under generic artifact paths.
For example, Superpowers brainstorming specs and writing-plans artifacts live
under:

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

The convention was later generalized into user-level Codex guidance. Because
`codex/.codex/AGENTS.md` applies across projects, the durable rule cannot be a
maintained list of forbidden scopes such as `spec`, `plan`, or a specific
generator name. It needs to describe the reasoning: choose the scope from the
staged document's affected component, product area, or domain. Artifact,
workflow, generator, and directory names are valid scopes only when that system
is genuinely what changed.

Codex session history search found no usable prior sessions for this generalized
guidance. One candidate session had a parse error and no selected matches.

## Guidance

Use commit scope to identify the affected component or domain. Do not use scope
to identify the kind of file being committed.

For generated or planning documentation, read the staged content before choosing
the scope. This applies to specs, plans, implementation notes, solution notes,
and other workflow-produced markdown. Prefer the affected component, product
area, or domain:

- Codex work: `docs(codex): ...`
- Claude work: `docs(claude): ...`
- read-once work: `docs(read-once): ...`
- Repo-wide policy with no concrete component: `docs: ...`

For user-level Codex instructions, keep the wording portable:

```text
Prefer: docs(<affected-component>): describe <change>
Avoid:  docs(<artifact-or-generator-name>): describe <change>
```

Do not infer scope from the document format, workflow name, generator name, or
directory name unless that system is genuinely what the commit changes. For
example, a generator name is a good scope when the commit changes the generator
or its own workflow. It is a weak scope when the generated document merely
describes another component.

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

The generalized Codex guidance was implemented as advisory text in
`codex/.codex/AGENTS.md`. The atomic commit hook stayed unchanged because it
should enforce mechanical safety, such as avoiding broad staging and
commit-all flags, not semantic judgment about what a generated document is
about.

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
history needs to know whether a generated document affected Codex, Claude,
read-once hooks, or general repo policy. Scopes based on artifact type hide that
information because they only repeat what the path already says.

Repository-name scopes have a similar problem. In a dotfiles repo, nearly every
change could be called `dotfiles`, so the scope adds little value. A concrete
component scope is better when one exists; an unscoped subject is clearer when
the change is genuinely repo-wide.

For user-level Codex config, hard-coded forbidden-scope lists create their own
maintenance problem. A term that is a bad artifact scope in one repository may
be a legitimate component in another. Principle-based guidance avoids that
drift while still steering Codex away from path-derived commit subjects.

History rewrites make small convention mistakes expensive. Once a bad scope is
rewritten through local history, remote-only commits need to be reconciled too.
Use `--force-with-lease`, not a blind force push, so the push refuses to
overwrite unexpected remote movement.

## When to Apply

- A generated spec, plan, implementation note, solution note, or workflow
  artifact needs a conventional commit subject.
- A commit subject uses an artifact, workflow, generator, directory, or generic
  repository name as the scope even though the staged content is about another
  component.
- User-level Codex commit guidance needs to apply across projects without
  maintaining a project-specific forbidden-scope list.
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

### Adding portable Codex guidance

The Codex instruction change used an abstract pattern instead of naming every
bad scope:

```text
Prefer: docs(<affected-component>): describe <change>
Avoid:  docs(<artifact-or-generator-name>): describe <change>
```

This belongs in `codex/.codex/AGENTS.md`, not the atomic commit hook, because
the hook should not try to infer semantic ownership from staged documentation.

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

- [Signal-driven commit-scope validation in PreToolUse hook](./commit-scope-signal-driven-validation-2026-05-21.md) operationalises this human convention as automated signals in `claude/.claude/lib/commit-scope.sh` + `claude/.claude/hooks/git-safety.sh`. The list-driven `BANNED_SCOPES` / `ARTIFACT_PREFIXES` approach is retired in favor of four signals derived from filesystem + `git log` history.
- [Superpowers workflow reorganization](../workflow-issues/superpowers-workflow-reorg-2026-05-19.md) covers the broader Superpowers workflow that produces specs and plans.
- [Subagent-driven mechanical edit fidelity](../workflow-issues/subagent-driven-mechanical-edit-fidelity-2026-05-19.md) is related workflow guidance for executing detailed plans without drifting from the requested edit.
- [Configure context-mode for Codex CLI](../tooling-decisions/configure-context-mode-for-codex-cli-2026-05-17.md) is related background for keeping Codex behavior in durable user-level config rather than ad hoc session behavior.
