# Codex Generated Document Commit Scopes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve user-level Codex commit guidance so generated and planning docs use commit scopes based on the affected component, product area, or domain.

**Architecture:** Keep hook enforcement unchanged and update only `codex/.codex/AGENTS.md`. The atomic commit hook continues to enforce mechanical staging safety; semantic scope choice remains advisory because this is user-level config that applies across projects.

**Tech Stack:** Markdown, Codex user instructions, Bash verification, existing Codex atomic commit hook tests.

---

## Source Material

- Design spec: `docs/superpowers/specs/2026-05-19-codex-generated-doc-commit-scopes-design.md`
- Target instructions: `codex/.codex/AGENTS.md`
- Existing hook tests: `codex/.codex/tests/test-atomic-commits-hook.sh`
- Existing hook implementation: `codex/.codex/hooks/atomic-commits.sh`

## File Structure

- Modify: `codex/.codex/AGENTS.md`
  - Responsibility: user-level Codex behavioral guidance that applies across repositories.
  - Add one portable subsection under `## Git Commit Workflow`.
- Read-only: `codex/.codex/hooks/atomic-commits.sh`
  - Responsibility: mechanical guardrail for broad staging and commit-all commands.
  - Do not change this file for this feature.
- Read-only test: `codex/.codex/tests/test-atomic-commits-hook.sh`
  - Responsibility: regression coverage proving the existing hook behavior still works.

## Task 1: Add Portable Generated-Doc Scope Guidance

**Files:**
- Modify: `codex/.codex/AGENTS.md`
- Test: `codex/.codex/tests/test-atomic-commits-hook.sh`

- [ ] **Step 1: Inspect the current Git Commit Workflow section**

Run:

```bash
sed -n '1,120p' codex/.codex/AGENTS.md
```

Expected: output includes `## Git Commit Workflow` and the existing scope rule:

```text
Choose commit scopes from recent project history when a clear scope exists.
```

- [ ] **Step 2: Add generated-document guidance**

Use `apply_patch` to insert this subsection immediately after the existing bullets about choosing commit scopes from recent project history:

```markdown
- For generated or planning documentation, choose the scope from the component,
  product area, or domain described by the staged content. Do not infer scope
  from the document format, workflow name, generator name, or directory name
  unless that system is genuinely what the commit changes.
  Prefer `docs(<affected-component>): describe <change>` over
  `docs(<artifact-or-generator-name>): describe <change>`. If the change is
  repo-wide and no component dominates, omit the scope.
```

The resulting section should read:

```markdown
- Choose commit scopes from recent project history when a clear scope exists.
  A new scope is acceptable when the project genuinely needs one.
- For generated or planning documentation, choose the scope from the component,
  product area, or domain described by the staged content. Do not infer scope
  from the document format, workflow name, generator name, or directory name
  unless that system is genuinely what the commit changes.
  Prefer `docs(<affected-component>): describe <change>` over
  `docs(<artifact-or-generator-name>): describe <change>`. If the change is
  repo-wide and no component dominates, omit the scope.
```

- [ ] **Step 3: Verify the guidance was inserted**

Run:

```bash
rg -n "generated or planning documentation|artifact-or-generator-name|repo-wide and no component dominates" codex/.codex/AGENTS.md
```

Expected: three matching lines from the new generated-document guidance.

- [ ] **Step 4: Verify the guidance stays portable**

Run:

```bash
rg -n "Superpowers|OpenSpec|docs\\(spec\\)|docs\\(plan\\)|docs\\(openspec\\)|docs\\(solution\\)|docs\\(dotfiles\\)" codex/.codex/AGENTS.md
```

Expected: no output and exit code `1`. The user-level instruction must not hard-code project-specific documentation systems or maintained bad-scope examples.

- [ ] **Step 5: Verify the hook was not modified**

Run:

```bash
git diff -- codex/.codex/hooks/atomic-commits.sh
```

Expected: no output. This feature is advisory and must not change hook enforcement.

- [ ] **Step 6: Run the atomic commit hook regression tests**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: all existing `ok denied:` and `ok allowed:` cases print successfully, and the command exits with status `0`.

- [ ] **Step 7: Review the full diff**

Run:

```bash
git diff -- codex/.codex/AGENTS.md
```

Expected: the diff only adds the generated-document scope guidance under `## Git Commit Workflow`.

- [ ] **Step 8: Commit the implementation**

Run:

```bash
git add codex/.codex/AGENTS.md
git commit -m "docs(codex): guide generated doc commit scopes"
```

Expected: commit succeeds. The `codex` scope is correct because the change updates Codex user-level guidance.
