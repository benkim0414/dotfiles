# Codex Generated Document Commit Scopes Design

## Context

Codex already has an atomic commit workflow in `codex/.codex/AGENTS.md` and a
focused `PreToolUse` hook in `codex/.codex/hooks/atomic-commits.sh`. The hook
blocks mechanical mistakes such as broad staging and commit-all commands. The
Git `commit-msg` hook validates conventional commit shape and recent scopes.

A recent cleanup documented a separate convention: generated planning documents
should not use commit scopes based only on their artifact path. A generated
document may describe one product area, one tool, one hook family, or repo-wide
policy. The same judgment applies across documentation systems: the scope should
come from what the staged content changes, not from the generator, workflow, or
directory that produced the file.

The existing hook should not infer semantic scope from document paths. Scope
choice requires reading the document content and understanding what component or
domain the document changes.

## Goal

Improve Codex's advisory atomic commit guidance so generated docs are committed
with scopes based on the affected component, product area, or domain. Because
this is user-level config, the guidance must stay portable across projects and
avoid hard-coded project-specific scope lists.

## Non-Goals

- Do not add hook enforcement for generated-document scopes.
- Do not replace the existing `commit-msg` conventional commit validator.
- Do not require a scope when a docs change is genuinely repo-wide.
- Do not hard-code a maintained list of forbidden artifact or generator scopes.
- Do not create a new helper script unless implementation discovers a clear
  gap that advisory text cannot cover.

## Recommended Approach

Update `codex/.codex/AGENTS.md` only. Add a concise subsection under the Git
commit workflow that explains generated-document scope selection.

Keep `codex/.codex/hooks/atomic-commits.sh` unchanged. Its boundary is
mechanical atomicity: prevent broad staging and commit-all shortcuts. Generated
document scope selection is semantic and belongs in instructions.

## Components

### Codex User Instructions

Extend `codex/.codex/AGENTS.md` with a generated-document scope rule:

- For generated or planning documentation, choose the commit scope from the
  component, product area, or domain described by the staged content.
- Do not infer scope from the document format, workflow name, generator name, or
  directory name unless that system is genuinely what the commit changes.
- Use unscoped `docs:` when the change is genuinely repo-wide and no component
  dominates.
- When unsure, inspect the staged files and recent subjects before committing.

Use an abstract example instead of a maintained list of project-specific scopes:

```text
Prefer: docs(<affected-component>): describe <change>
Avoid:  docs(<artifact-or-generator-name>): describe <change>
```

Artifact or generator names remain valid scopes when the commit changes that
artifact system or generator itself. The instruction should forbid the reasoning
error, not specific words that may be legitimate components in another project.

### Atomic Commit Hook

Leave `codex/.codex/hooks/atomic-commits.sh` as-is. It should continue to
reject broad staging and commit-all commands, but it should not attempt to parse
staged documentation and guess the correct semantic scope.

### Commit Message Hook

Leave `git/.config/git/hooks/commit-msg` as-is. It validates conventional
commit shape, subject length, and whether a scoped commit uses a recent known
scope. The new Codex guidance helps choose better scopes before that hook runs.

## Data Flow

1. Codex loads user-level instructions from `codex/.codex/AGENTS.md`.
2. During commit preparation, Codex stages explicit files for one logical
   change.
3. If the staged files are generated docs, Codex reads their content to identify
   the affected component, product area, or domain.
4. Codex chooses a conventional commit subject using that component scope, or
   omits scope for repo-wide docs.
5. The existing Git hook validates the final subject.

## Error Handling

If scope choice is unclear, Codex should inspect:

- `git diff --cached --name-only`
- `git diff --cached`
- `git log --format=%s -50`

For generated docs, path alone is insufficient. If the staged content describes
one component, product area, or domain, use that as the scope. If it describes a
repo-wide policy without a dominant component, use unscoped `docs:`.

If the `commit-msg` hook rejects a scope, Codex should read the rejection,
inspect recent subjects, and retry with a valid subject. It should not switch to
artifact or generator scopes just because the file lives in a generated-doc
directory.

## Testing

Verification should stay lightweight because the change is advisory:

- Check that `codex/.codex/AGENTS.md` contains generated-document scope
  guidance.
- Check that the guidance is portable user-level advice, not tied to one
  project, workflow, or documentation generator.
- Check that it uses an abstract anti-pattern rather than a maintained list of
  forbidden scopes.
- Run `codex/.codex/tests/test-atomic-commits-hook.sh` to confirm existing hook
  behavior remains unchanged.
- Optionally inspect recent history for obsolete generated-doc scopes when
  committing or rewriting docs-heavy work.
