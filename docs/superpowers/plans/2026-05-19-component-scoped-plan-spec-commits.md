# Component-Scoped Plan and Spec Commits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite local commit messages so Superpowers spec and plan commits use concrete component scopes such as `codex` or `claude`, not artifact scopes such as `spec` or `plan`; repo-wide changes omit the scope.

**Architecture:** This is a message-only history rewrite. Use an explicit subject map over the affected local history range, then verify that the final tree is unchanged and that no reachable Superpowers plan/spec commit still uses artifact scopes.

**Tech Stack:** Git, POSIX shell, `sed`, `rg`

---

## File Structure

- Create: `docs/superpowers/plans/2026-05-19-component-scoped-plan-spec-commits.md`
  - This implementation plan.
- Read-only: `docs/superpowers/specs/2026-05-19-component-scoped-plan-spec-commits-design.md`
  - Approved design source for the rewrite policy.
- No tracked source files should be modified by execution.
  - The implementation changes commit metadata only.

## Message Map

Use this exact mapping for currently reachable artifact-scoped subjects:

| Current subject | New subject |
| --- | --- |
| `docs(plan): subagent approval inheritance` | `docs(codex): plan subagent approval inheritance` |
| `docs(spec): subagent approval inheritance` | `docs(codex): design subagent approval inheritance` |
| `docs(plan): context-mode plugin install + remember cleanup` | `docs(claude): plan context-mode plugin install + remember cleanup` |
| `docs(spec): split alphabetize step into its own commit` | `docs(claude): design split alphabetize step into its own commit` |
| `docs(spec): context-mode plugin install + remember cleanup` | `docs(claude): design context-mode plugin install + remember cleanup` |
| `docs(spec, plan): add Task 6.5 wiki plugin + bootstrap removal` | `docs(claude): update workflow reorg plan and spec for wiki removal` |
| `docs(plan): superpowers workflow reorganization implementation plan` | `docs(claude): plan superpowers workflow reorganization` |
| `docs(spec): superpowers workflow reorganization design` | `docs(claude): design superpowers workflow reorganization` |
| `docs(plan): context-mode approval` | `docs(codex): plan context-mode approval` |
| `docs(spec): context-mode approval` | `docs(codex): design context-mode approval` |
| `docs(spec): single-source hook config` | `docs(codex): design single-source hook config` |
| `docs(plan): plugin source of truth` | `docs(codex): plan plugin source of truth` |
| `docs(spec): plugin source of truth` | `docs(codex): design plugin source of truth` |
| `docs(plan): context-mode setup` | `docs(codex): plan context-mode setup` |
| `docs(spec): context-mode setup` | `docs(codex): design context-mode setup` |
| `docs(plan): finish worktree approval plan` | `docs(codex): finish worktree approval plan` |
| `docs(plan): worktree git approval` | `docs(codex): plan worktree git approval` |
| `docs(spec): record worktree approval limitation` | `docs(codex): record worktree approval limitation` |
| `docs(spec): worktree git approval` | `docs(codex): design worktree git approval` |
| `docs(plan): keep commit workflow docs codex-only` | `docs(codex): keep commit workflow docs codex-only` |
| `docs(plan): atomic commit workflow` | `docs(codex): plan atomic commit workflow` |
| `docs(spec): clarify user-level commit workflow` | `docs(codex): clarify user-level commit workflow` |
| `docs(spec): atomic commit workflow` | `docs(codex): design atomic commit workflow` |

### Task 1: Capture Baseline

**Files:**
- Read-only: git history

- [ ] **Step 1: Record the current branch tip**

Run:

```bash
git rev-parse HEAD
```

Expected: prints the current tip commit. Save this SHA mentally as `BASELINE_HEAD` for the later tree comparison.

- [ ] **Step 2: Confirm the affected subjects are present**

Run:

```bash
git log --format='%h %s' -- docs/superpowers/specs docs/superpowers/plans | rg 'docs\((spec|plan|spec, plan)\):'
```

Expected: prints the artifact-scoped subjects from the Message Map. If it prints nothing, the rewrite has already been applied and the remaining tasks should become verification only.

- [ ] **Step 3: Confirm unrelated untracked files before rewriting**

Run:

```bash
git status --short
```

Expected: only the known unrelated untracked files may appear:

```text
?? docs/superpowers/plans/2026-05-16-tmux-ipad-osc52-clipboard.md
?? docs/superpowers/plans/2026-05-17-codex-hooks-single-source.md
```

If other tracked modifications appear, stop and inspect them before rewriting history.

### Task 2: Rewrite Commit Messages

**Files:**
- Modify: commit metadata only
- Do not modify tracked file contents

- [ ] **Step 1: Run the explicit message rewrite**

Run:

```bash
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --msg-filter '
sed \
  -e "s/^docs(plan): subagent approval inheritance$/docs(codex): plan subagent approval inheritance/" \
  -e "s/^docs(spec): subagent approval inheritance$/docs(codex): design subagent approval inheritance/" \
  -e "s/^docs(plan): context-mode plugin install + remember cleanup$/docs(claude): plan context-mode plugin install + remember cleanup/" \
  -e "s/^docs(spec): split alphabetize step into its own commit$/docs(claude): design split alphabetize step into its own commit/" \
  -e "s/^docs(spec): context-mode plugin install + remember cleanup$/docs(claude): design context-mode plugin install + remember cleanup/" \
  -e "s/^docs(spec, plan): add Task 6.5 wiki plugin + bootstrap removal$/docs(claude): update workflow reorg plan and spec for wiki removal/" \
  -e "s/^docs(plan): superpowers workflow reorganization implementation plan$/docs(claude): plan superpowers workflow reorganization/" \
  -e "s/^docs(spec): superpowers workflow reorganization design$/docs(claude): design superpowers workflow reorganization/" \
  -e "s/^docs(plan): context-mode approval$/docs(codex): plan context-mode approval/" \
  -e "s/^docs(spec): context-mode approval$/docs(codex): design context-mode approval/" \
  -e "s/^docs(spec): single-source hook config$/docs(codex): design single-source hook config/" \
  -e "s/^docs(plan): plugin source of truth$/docs(codex): plan plugin source of truth/" \
  -e "s/^docs(spec): plugin source of truth$/docs(codex): design plugin source of truth/" \
  -e "s/^docs(plan): context-mode setup$/docs(codex): plan context-mode setup/" \
  -e "s/^docs(spec): context-mode setup$/docs(codex): design context-mode setup/" \
  -e "s/^docs(plan): finish worktree approval plan$/docs(codex): finish worktree approval plan/" \
  -e "s/^docs(plan): worktree git approval$/docs(codex): plan worktree git approval/" \
  -e "s/^docs(spec): record worktree approval limitation$/docs(codex): record worktree approval limitation/" \
  -e "s/^docs(spec): worktree git approval$/docs(codex): design worktree git approval/" \
  -e "s/^docs(plan): keep commit workflow docs codex-only$/docs(codex): keep commit workflow docs codex-only/" \
  -e "s/^docs(plan): atomic commit workflow$/docs(codex): plan atomic commit workflow/" \
  -e "s/^docs(spec): clarify user-level commit workflow$/docs(codex): clarify user-level commit workflow/" \
  -e "s/^docs(spec): atomic commit workflow$/docs(codex): design atomic commit workflow/"
' '3d6d6ea^..HEAD'
```

Expected: `Ref 'refs/heads/main' was rewritten`.

If the lower-bound commit is no longer named `3d6d6ea`, find the oldest artifact-scoped Superpowers spec/plan commit with:

```bash
git log --reverse --format='%h %s' -- docs/superpowers/specs docs/superpowers/plans | rg 'docs\((spec|plan|spec, plan)\):' | head -1
```

Then rerun the rewrite using `<oldest-sha>^..HEAD`.

- [ ] **Step 2: Remove the temporary filter-branch backup ref**

Run:

```bash
git update-ref -d refs/original/refs/heads/main
```

Expected: no output. If the ref does not exist, the command still exits successfully or reports nothing actionable.

### Task 3: Verify Rewritten History

**Files:**
- Read-only: git history

- [ ] **Step 1: Check that artifact scopes are gone from plan/spec commits**

Run:

```bash
git log --format='%h %s' -- docs/superpowers/specs docs/superpowers/plans | rg 'docs\((spec|plan|spec, plan)\):'
```

Expected: exit code `1` with no output.

- [ ] **Step 2: Inspect the rewritten Superpowers plan/spec subjects**

Run:

```bash
git log --format='COMMIT %h %s' --name-only -- docs/superpowers/specs docs/superpowers/plans | head -180
```

Expected: subjects use component scopes. Examples near the top should include:

```text
COMMIT <sha> docs: design component-scoped plan spec commits
COMMIT <sha> docs(codex): plan subagent approval inheritance
COMMIT <sha> docs(codex): design subagent approval inheritance
COMMIT <sha> docs(claude): plan context-mode plugin install + remember cleanup
COMMIT <sha> docs(claude): design context-mode plugin install + remember cleanup
```

- [ ] **Step 3: Confirm final tree content did not change**

Run:

```bash
git diff --stat BASELINE_HEAD HEAD
```

Replace `BASELINE_HEAD` with the SHA captured in Task 1.

Expected: no output.

- [ ] **Step 4: Confirm the working tree still only has unrelated untracked files**

Run:

```bash
git status --short --branch
```

Expected: branch divergence reflects the rewrite. Only the known unrelated untracked files may appear:

```text
?? docs/superpowers/plans/2026-05-16-tmux-ipad-osc52-clipboard.md
?? docs/superpowers/plans/2026-05-17-codex-hooks-single-source.md
```

### Task 4: Report Result

**Files:**
- No file changes

- [ ] **Step 1: Summarize rewritten policy**

Report:

```text
Plan/spec commit subjects now use component scopes derived from document contents:
- Codex plan/specs use docs(codex)
- Claude plan/specs use docs(claude)
- Repo-level policy specs use unscoped docs:
```

- [ ] **Step 2: Mention force-push requirement**

Report:

```text
Because this rewrites local history already based on origin/main, publishing requires git push --force-with-lease.
```

- [ ] **Step 3: Mention untouched unrelated files**

Report:

```text
Unrelated untracked plan files were left untouched:
- docs/superpowers/plans/2026-05-16-tmux-ipad-osc52-clipboard.md
- docs/superpowers/plans/2026-05-17-codex-hooks-single-source.md
```

## Self-Review

- Spec coverage: Tasks cover component-scoped rewriting, artifact-scope removal, tree-preservation verification, and untouched untracked files.
- Placeholder scan: No placeholders remain.
- Scope check: The plan changes commit metadata only and does not introduce hooks, directory layout changes, or implementation file edits.
