# Global CLAUDE.md Trim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce `claude/.claude/CLAUDE.md` to commit rules only, relocating the commit-scope signals to the dotfiles project file and the superpowers workflow to an untracked `ops/CLAUDE.local.md`.

**Architecture:** Three independent file changes. Two land in this repo as separate commits; the third writes an untracked file into `~/workspace/ops` and is ignored there through `.git/info/exclude`, so it produces no commit anywhere. Hooks, settings, and `~/.claude/docs/superpowers-workflow.md` are untouched.

**Tech Stack:** Markdown, GNU Stow symlinks, bash 3.2 test harnesses.

**Spec:** `docs/superpowers/specs/2026-09-21-global-config-trim-design.md`

## Global Constraints

- Hooks, `settings.base.json`, `settings.overlay.json`, and `~/.claude/docs/superpowers-workflow.md` must not change. The spec's D5 defers hook removal to its own project.
- `CLAUDE.company.md` stays on disk. Do not delete it.
- Stage explicit paths only: `git add <path>`. Never `-A`, `.`, `--all`, `--update`, `git commit -a`, `git commit -am`.
- Commit scope is `claude` — 95 uses in this repo's history, and both changed files belong to the claude package's surface.
- All commands run from the worktree root, `/Users/ben/workspace/dotfiles/.claude/worktrees/global-config-trim`. Never `cd` to the main checkout.
- Task 3 writes outside this repo. That is allowed: `worktree-guard.sh` exits 0 when the resolved path is not under `git rev-parse --show-toplevel`.

## Verified preconditions

Checked before this plan was written; re-checking is not required.

- No test asserts on `CLAUDE.md` content. The five suites that mention it use the path as a fixture (`permission-policy/cases/06`, `08`), name it in a comment (`commit-scope/cases/71`, `bash-portability/run.sh`), or exclude it from a grep (`caveman-default-off/run.sh`).
- `# Brewfile rules` occurs exactly once in `CLAUDE.md`, at line 398, and is a safe Edit anchor.
- `claude/.claude/CLAUDE.md` is 297 lines. `CLAUDE.md` is 410 lines.

---

### Task 1: Move the commit-scope signals into the dotfiles project file

The `git-safety.sh` hook and `commit-scope.sh` lib both live in this repo, so documenting their signals here is a delta rather than a restatement of the global. Heading levels are promoted: `#### Scope = ...` becomes a top-level `# Commit scope`, and `#### Examples` becomes `## Examples`, matching the `#`/`##` structure the file already uses.

This is a separate commit from Task 2 because Task 2 deletes twelve sections, only one of which is relocated here. A reviewer could reasonably accept this addition and reject that deletion.

**Files:**
- Modify: `CLAUDE.md` — insert a new section immediately before `# Brewfile rules` (currently line 398)

**Interfaces:**
- Consumes: nothing
- Produces: a `# Commit scope` section in `CLAUDE.md` that Task 2 relies on existing before it deletes the original

- [ ] **Step 1: Confirm the anchor is unique**

Run:

```bash
grep -c '^# Brewfile rules$' CLAUDE.md
```

Expected: `1`

- [ ] **Step 2: Insert the section**

Use Edit on `CLAUDE.md`.

`old_string`:

```
# Brewfile rules
```

`new_string`:

````
# Commit scope

Scope identifies WHAT the commit changes, not WHERE the artifact lives.
Read the file contents before choosing scope. The
`claude/.claude/hooks/git-safety.sh` hook emits a non-blocking warning
when the declared scope fails any of these signals (see
`claude/.claude/lib/commit-scope.sh` for the canonical implementation):

- **S1 - Universal container**: scope is a filesystem-convention
  container name (`docs`, `src`, `lib`, `bin`, `tests`, `scripts`,
  `packages`, `apps`, etc.) AND scope is not already in the repo's
  `git log` history.
- **S2 - Repo basename**: scope equals the current repository's
  directory name (e.g. scope `myapp` in repo `myapp/`). No history
  escape - repo names never identify a component.
- **S3 - Path-segment match**: scope (or its `+s` plural form) equals
  a directory segment of the staged file paths, AND scope is not in
  `git log` history. Catches `docs(spec)` when staging under
  `docs/superpowers/specs/`, `docs(openspec)` when staging under
  `openspec/changes/`, and any future framework that publishes to a
  documentation directory.
- **S4 - New-scope advisory** (soft): scope is allowed by S1-S3 but is
  not in `git log` history. Verify the scope names a component, not an
  artifact directory.

Real scopes are whatever component names appear in the current repo's
`git log`. Examples below use `<component>` placeholders; substitute
your repo's actual components.

## Examples

```text
# Good
feat(<component>): <description>                 # scope names the affected component
docs(<component>): update <component> docs       # same
docs: <repo-wide policy change>                  # unscoped when no concrete component dominates

# Bad
feat(spec): <description>                        # 'spec' = artifact type (S3: matches 'specs/' segment)
feat(plan): <description>                        # 'plan' = artifact type (S3: matches 'plans/' segment)
docs(<repo-name>): <description>                 # repo name = location (S2)
docs(openspec): <description>                    # framework name (S3: matches 'openspec/' segment)
docs(docs): <description>                        # universal container (S1)
feat(<component>): change X and Y                # "and" = two changes -> split
```

# Brewfile rules
````

- [ ] **Step 3: Verify the section landed at the right level**

Run:

```bash
grep -n '^# Commit scope$\|^## Examples$\|^# Brewfile rules$' CLAUDE.md
```

Expected: three lines, in that order, with `# Commit scope` before `# Brewfile rules`.

- [ ] **Step 4: Verify all four signals survived the move**

Run:

```bash
grep -c '^- \*\*S[1-4] - ' CLAUDE.md
```

Expected: `4`

- [ ] **Step 5: Verify no heading level was left at `####`**

Run:

```bash
sed -n '/^# Commit scope$/,/^# Brewfile rules$/p' CLAUDE.md | grep -c '^####'
```

Expected: `0`

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git diff --cached --name-only
git commit -m "docs(claude): document the commit-scope signals in the project file" -m "The git-safety.sh hook and commit-scope.sh lib live in this repo, so the S1-S4 signals belong here rather than in the per-user global file. Heading levels promoted to match the file's existing structure." -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

`git diff --cached --name-only` must print exactly `CLAUDE.md` before you commit.

---

### Task 2: Reduce the global file to commit rules

Replace `claude/.claude/CLAUDE.md` wholesale. The result is 11 lines; the spec's "13 lines" counted the surrounding code fence.

**Files:**
- Modify: `claude/.claude/CLAUDE.md` — full replacement, 297 lines to 11

**Interfaces:**
- Consumes: the `# Commit scope` section added by Task 1
- Produces: nothing later tasks depend on

- [ ] **Step 1: Record the starting state**

Run:

```bash
wc -l < claude/.claude/CLAUDE.md
```

Expected: `297`

- [ ] **Step 2: Replace the file**

Use Write on `claude/.claude/CLAUDE.md` with exactly this content:

````markdown
# Commit rules

One commit = one logical change. Split when the subject needs "and",
when staged files span unrelated areas, or when a fix and a refactor
are mixed.

Stage explicit paths: `git add <path>`. Never `-A`, `.`, `--all`,
`--update`, `git commit -a`, `git commit -am`.

Form: `type(scope): description`. Types: feat, fix, docs, chore,
refactor, test, ci, perf.
````

- [ ] **Step 3: Verify the file is exactly what was specified**

Run:

```bash
wc -l < claude/.claude/CLAUDE.md
head -1 claude/.claude/CLAUDE.md
```

Expected: `11`, then `# Commit rules`.

- [ ] **Step 4: Verify every removed section is gone**

Run:

```bash
grep -cE 'CLAUDE\.company|Execution handoff|Canonical workflow|mcp-compressor|Semantic Search|Plugin integration|No-pr mode|Worktree exit|S1 - Universal' claude/.claude/CLAUDE.md
```

Expected: `0`. `grep -c` exits 1 when it finds nothing, which is the passing case here — read the printed count, not the exit status.

- [ ] **Step 5: Verify `CLAUDE.company.md` still exists and was not edited**

Run:

```bash
test -f claude/.claude/CLAUDE.company.md && echo present
git status --porcelain claude/.claude/CLAUDE.company.md
```

Expected: `present`, then no output.

**Amended after execution:** a later commit on this branch edited
`CLAUDE.company.md` to correct its header, which had claimed the global file
imports it. The assertion above holds at the end of Task 2 and no longer holds
at the tip of the branch. What must stay true is that the file is never
deleted.

- [ ] **Step 6: Verify hooks and settings are untouched**

Run:

```bash
git status --porcelain claude/.claude/hooks claude/.claude/lib claude/.claude/settings.base.json claude/.claude/settings.overlay.json claude/.claude/docs
```

Expected: no output.

- [ ] **Step 7: Check for references that now dangle**

Run:

```bash
grep -rn 'CLAUDE\.company' --include='*.md' --include='*.sh' --include='*.json' . | grep -v '^\./docs/' | grep -v '^\./\.claude/worktrees/'
```

Expected: hits in `CLAUDE.md` (the "Claude Code settings" section describes the layered merge) are fine and stay. Any hit that tells a reader the global file imports the company file is now wrong — report it rather than fixing it silently, because editing those sections is beyond this plan's scope.

- [ ] **Step 8: Run the affected suites**

Run:

```bash
bash claude/.claude/tests/commit-scope/run.sh
bash claude/.claude/tests/permission-policy/run.sh
bash claude/.claude/tests/bash-portability/run.sh
bash claude/.claude/tests/output-style/run.sh
bash caveman/tests/caveman-default-off/run.sh
bash bin/tests/stow-hygiene/run.sh
```

Expected: every suite exits 0. These six are the suites that mention `CLAUDE.md` plus the stow-hygiene guard. If any fails, stop and report — do not adjust the test to match.

- [ ] **Step 9: Commit**

```bash
git add claude/.claude/CLAUDE.md
git diff --cached --name-only
git commit -m "docs(claude): reduce the global instructions to commit rules" -m "Drop the company import, preferences, response style, verification, qmd, the mcp-compressor post-mortem, the workflow chain, both execution handoffs, PR and no-pr mode, worktree exit, and plugin integration. The workflow moves to per-project config so each repo can run the flow its characteristics call for." -m "CLAUDE.company.md stays on disk, unreferenced, as the source for per-project company config." -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

`git diff --cached --name-only` must print exactly `claude/.claude/CLAUDE.md` before you commit.

---

### Task 3: Create the ops workflow file

Writes an untracked file into a different repository. **This task produces no commit in either repo.** Step 4 is blocking: if the sentinel does not reach a linked worktree, stop and apply the fallback in Step 7 rather than proceeding.

**Files:**
- Create: `/Users/ben/workspace/ops/CLAUDE.local.md` — untracked
- Modify: `/Users/ben/workspace/ops/.git/info/exclude` — append one line

**Interfaces:**
- Consumes: nothing
- Produces: nothing

- [ ] **Step 1: Ignore the file before creating it**

Creating the file first would briefly expose it to `git status` in a shared repo. Run:

```bash
printf 'CLAUDE.local.md\n' >> /Users/ben/workspace/ops/.git/info/exclude
tail -3 /Users/ben/workspace/ops/.git/info/exclude
```

Expected: the last line is `CLAUDE.local.md`.

- [ ] **Step 2: Write the file with a sentinel**

Use Write on `/Users/ben/workspace/ops/CLAUDE.local.md` with exactly this content. The `PERSONAL_WORKFLOW_SENTINEL` line is temporary and is removed in Step 6.

````markdown
# Personal workflow

Untracked and not shared. `AGENTS.md` is the team contract; this file is
mine alone.

PERSONAL_WORKFLOW_SENTINEL: loaded-ok

## Canonical workflow

```
EnterWorktree
    ↓
brainstorming                   (design + spec)
    ↓
writing-plans                   (step-by-step plan)
    ↓
subagent-driven-development     (TDD + systematic-debugging inline)
    ↓
verification-before-completion
    ↓
requesting-code-review          (re-invoke after fixes until clean)
    ↓
ce-compound                     (capture learnings -> docs/solutions/)
    ↓
finishing-a-development-branch  option 2 (push + gh pr create)
    ↓
receiving-code-review           (reactive, on reviewer feedback)
    ↓
gh pr merge --merge
    ↓
ExitWorktree("keep")
```

All plan artifacts live inside the worktree and merge with the feature:
`docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/solutions/`.

Quick fixes skip `brainstorming` and `writing-plans`. `ce-compound` is
optional for them — invoke it only when the fix has reusable lessons.

## Execution handoff after `writing-plans`

When `superpowers:writing-plans` finishes saving the plan and reaches its
"Execution Handoff" section, do NOT prompt with the "Which approach?"
question. Pick the execution path and announce the choice in one line, then
proceed.

1. **Default:** `superpowers:subagent-driven-development` — the option the
   skill itself marks as recommended. Use this when tasks are meaningfully
   independent and dispatching subagents adds value.
2. **Exception — orchestrator-direct:** when the plan contains the exact
   final code and the tasks are mechanical edits (regex tweaks, single-block
   deletions, comment updates, line insertions), execute the edits inline
   from the orchestrator without dispatching subagents. Subagent round-trips
   on mechanical edits add latency and edit-fidelity risk without adding
   value.
3. **Exception — `superpowers:executing-plans`:** when tightly-coupled tasks
   benefit from batched checkpoints rather than per-task review.

Announce in one line, such as `Auto-invoking subagent-driven-development.`
or `Mechanical edits — executing from orchestrator.`

Override: if a different execution path is named in the same turn, honour
that instead.

## Execution handoff for `ce-compound`

When `compound-engineering:ce-compound` reaches an interactive blocking
prompt, do NOT ask. Auto-select and announce, except where noted.

1. **Full vs Lightweight** -> always **Full**, the option the skill marks
   `(recommended)`.
2. **Session history** -> default to **skipping**; the skill flags added time
   and token cost. Opt in only when the documented problem clearly spans
   multiple prior sessions. State which was chosen.
3. **Discoverability Check consent** -> if the check finds a gap, apply the
   smallest fitting edit directly; if not, move on. No prompt either way.
4. **"What's next?" menu** -> present it normally. Do NOT auto-select. This
   repo is PR mode, and pushing plus opening a PR is outward-facing.

Override: if a different choice is named in the same turn, honour that
instead.

## Merge

- Merge commits only: `gh pr merge --merge`. Never squash, never rebase.
- After merge: `ExitWorktree("keep")`.
- `ExitWorktree("remove")` only for exploratory work with no commits.

## Plugin caveats

- Worktrees use the harness `EnterWorktree` / `ExitWorktree` tools, not
  `superpowers:using-git-worktrees`.
- Parallel agents: `caveman:cavecrew` for compressed delegation when context
  budget matters; `superpowers:dispatching-parallel-agents` otherwise.
````

- [ ] **Step 3: Verify the file is invisible to git (spec V2)**

Run:

```bash
cd /Users/ben/workspace/ops && git status --porcelain | grep CLAUDE.local.md; echo "exit=$?"
cd /Users/ben/workspace/ops && git check-ignore -v CLAUDE.local.md
```

Expected: the first command prints only `exit=1` (no match). The second names `.git/info/exclude`.

- [ ] **Step 4: Verify the file loads from the main worktree and a linked worktree (spec V1, BLOCKING)**

Run:

```bash
cd /Users/ben/workspace/ops && \
  claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."

cd /Users/ben/workspace/ops/.claude/worktrees/infra-592-baseline && \
  claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."
```

Expected: both print `loaded-ok`.

If the first returns `NONE`, the file is not being read at all — stop and report.
If the first returns `loaded-ok` and the second returns `NONE`, go to Step 7.

- [ ] **Step 5: Verify `AGENTS.md` was not modified**

Run:

```bash
cd /Users/ben/workspace/ops && git status --porcelain AGENTS.md CLAUDE.md .gitignore
```

Expected: no output. The shared contract and the shared ignore file must be untouched.

- [ ] **Step 6: Remove the sentinel**

Use Edit on `/Users/ben/workspace/ops/CLAUDE.local.md`.

`old_string`:

```
PERSONAL_WORKFLOW_SENTINEL: loaded-ok

## Canonical workflow
```

`new_string`:

```
## Canonical workflow
```

Then run:

```bash
grep -c PERSONAL_WORKFLOW_SENTINEL /Users/ben/workspace/ops/CLAUDE.local.md
```

Expected: `0`.

- [ ] **Step 7: Fallback, only if Step 4's worktree run returned `NONE`**

The upward walk did not cross into the repo from `.claude/worktrees/`. Switch to the documented home-directory import.

```bash
mv /Users/ben/workspace/ops/CLAUDE.local.md /Users/ben/.claude/ops-workflow.md
```

Then use Write on `/Users/ben/workspace/ops/CLAUDE.local.md` with:

```markdown
@~/.claude/ops-workflow.md
```

Re-run Step 4. Claude Code shows a one-time external-import approval dialog on the first session in this project; accept it. Both runs must then print `loaded-ok`.

Note in your task report that the fallback was taken — it changes the spec's D2 outcome, because the workflow text then lives in `~/.claude/` rather than inside ops.

- [ ] **Step 8: Confirm no commit is pending in either repo**

Run:

```bash
cd /Users/ben/workspace/ops && git status --porcelain
cd /Users/ben/workspace/dotfiles/.claude/worktrees/global-config-trim && git status --porcelain
```

Expected: no output from either. This task commits nothing.

---

## Post-merge check

Not a task — run after `finishing-a-development-branch` merges to main. The stowed symlink points at the main checkout, so it cannot pass before then.

```bash
readlink ~/.claude/CLAUDE.md
head -1 ~/.claude/CLAUDE.md
wc -l < ~/.claude/CLAUDE.md
```

Expected: the symlink resolves to `../workspace/dotfiles/claude/.claude/CLAUDE.md`, the first line is `# Commit rules`, and the count is `11`.

No `claude-sync` run is needed. It regenerates `~/.claude/settings.json` from the base and overlay, neither of which this plan touches; `CLAUDE.md` reaches `~/.claude/` through the existing Stow symlink.

## Self-review

**Spec coverage.** Change 1 (global replacement) is Task 2. Change 2 (commit-scope relocation) is Task 1. Change 3 (`ops/CLAUDE.local.md`) and change 4 (`.git/info/exclude`) are Task 3. V1 is Task 3 Step 4, V2 is Task 3 Step 3, V3 is Task 2 Step 8, V4 is Task 2 Step 7, V5 is the post-merge check. D5's "hooks untouched" is Task 2 Step 6 plus a global constraint. The spec's out-of-scope items produce no tasks, as intended.

**Placeholder scan.** No TBD, TODO, or "similar to Task N". Every file's content is given in full; the moved section is reproduced verbatim rather than described.

**Type consistency.** The sentinel string `PERSONAL_WORKFLOW_SENTINEL` and its value `loaded-ok` are identical in Steps 2, 4, 6, and 7. The anchor `# Brewfile rules` matches the verified line 398. The commit scope `claude` is used in both commits.

**One discrepancy, resolved:** the spec says the new global file is 13 lines; it is 11. The spec counted the surrounding code fence. Task 2 asserts 11, and the spec has since been corrected.

## Deviations taken during execution

Recorded so the plan matches the branch it describes.

1. **Task 2 Step 7 said report, not fix.** Three passages claimed the global file imports `CLAUDE.company.md`, which Task 2 had just made false. They were fixed in their own commit rather than merely reported, because the preceding commit created the falsehood and leaving it would ship self-contradicting documentation.
2. **One hook was edited, against the plan's global constraint.** `git-safety.sh:246` and `:292` pointed at `CLAUDE.md > Commit rules > Scope`, a path that resolves in no file after Task 1. Both now read `CLAUDE.md > Commit scope`. Text-only, no test asserts the wording, approved explicitly before the edit. The constraint defers hook removal, which remains untouched.
3. **`## Examples` was renamed `## Commit scope examples`** in the project file — a review finding, not part of any task.
