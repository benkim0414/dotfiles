# Codex Merge-to-Main Approval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex ask for direct user approval before agent-initiated merges into `main`, covering both PR merges and local no-PR worktree merges, without adding a blocking hook.

**Approved spec:** `docs/superpowers/specs/2026-05-22-codex-merge-main-approval-design.md`

**Architecture:** Keep the behavior in Codex approval/instruction surfaces. `codex/.codex/config.base.toml` remains the durable auto-review policy source. `codex/.codex/AGENTS.md` mirrors the agent-readable contract. `codex/.codex/config.toml` is regenerated for verification only and remains uncommitted if ignored.

## Task 1: Update Auto-Review Policy

**Files:**
- Modify: `codex/.codex/config.base.toml`
- Generated for verification: `codex/.codex/config.toml`

- [ ] **Step 1: Inspect the current policy block**

Run:

```bash
sed -n '/^\[auto_review\]/,/^\[features\]/p' codex/.codex/config.base.toml
```

Expected: output includes `Approve routine sandbox-compatible repository work`, routine GitHub-scoped operations, and sensitive operations that require direct user approval.

- [ ] **Step 2: Replace only the `[auto_review].policy` text**

In `codex/.codex/config.base.toml`, keep the surrounding TOML structure unchanged and replace the policy string with this text:

```toml
policy = """
Approve routine sandbox-compatible repository work: read-only commands, status
inspection, diffs, formatting checks, and test commands that write only inside
the active workspace or temporary directories.

Approve GitHub-scoped collaboration and branch sync commands when they are run
from the active repository worktree and are limited to ordinary PR, issue,
fetch, pull, or push workflows. This includes GitHub CLI PR view, list,
create, edit, comment, check, status, and review operations; GitHub CLI issue
view, list, create, edit, comment, and status operations; git fetch; git pull;
and ordinary non-force current-branch git push to GitHub remotes.

Deny destructive commands, broad arbitrary shell approvals, credential access,
writes outside configured workspace roots, non-GitHub network access, direct
GitHub API access through arbitrary runtimes or shell scripts, GitHub merge
operations including gh pr merge, local merge-to-main operations such as git
checkout main followed by git merge <branch>, branch deletion, repository
administration, settings or secrets changes, destructive issue or PR
operations, force pushes, history rewrites, and broad branch mutation commands.
These sensitive operations require direct user approval and must not be
approved by auto-review.

When an approval request includes a persistent prefix rule, approve only narrow
operation-specific prefixes such as gh pr view, gh pr list, gh pr create, gh pr
edit, gh pr comment, gh pr check, gh pr status, gh pr review, gh issue view,
gh issue list, gh issue create, gh issue edit, gh issue comment, and gh issue
status. Under the current prefix-rule model, git network commands (git fetch,
git pull, git push) should use per-command approval unless the approval
mechanism can enforce the exact GitHub, active-worktree, and non-destructive
constraints. Do not approve broad runtime prefixes such as bash, python, node,
ruby, perl, or sh.
"""
```

- [ ] **Step 3: Verify the policy includes the new merge-to-main boundary**

Run:

```bash
rg -n 'routine sandbox-compatible|GitHub-scoped|gh pr merge|merge-to-main|git checkout main|git merge <branch>|direct user approval|must not be approved by auto-review' codex/.codex/config.base.toml
```

Expected: output includes the routine allow language plus all merge-to-main direct-approval phrases.

## Task 2: Mirror the Contract in AGENTS

**Files:**
- Modify: `codex/.codex/AGENTS.md`

- [ ] **Step 1: Inspect the approval contract**

Run:

```bash
sed -n '1,24p' codex/.codex/AGENTS.md
```

Expected: output includes the `Subagent Approval Contract` section.

- [ ] **Step 2: Update the sensitive-operations bullet**

In `codex/.codex/AGENTS.md`, replace the sensitive operations bullet with this bullet:

```markdown
- Sensitive operations require direct user approval and must not be approved by auto-review: `gh pr merge`, GitHub merge operations, local merge-to-main operations such as `git checkout main` followed by `git merge <branch>`, branch deletion, repository administration, settings or secrets changes, destructive issue or PR operations, force pushes, history rewrites, credential access, non-GitHub network access, direct GitHub API access through arbitrary runtimes or shell scripts, destructive commands, and writes outside configured workspace roots.
```

Leave the routine-work, GitHub-scoped allowance, persistent-prefix, git-network, and broad-runtime bullets unchanged.

- [ ] **Step 3: Verify AGENTS mirrors the policy**

Run:

```bash
rg -n 'gh pr merge|GitHub merge operations|local merge-to-main|git checkout main|git merge <branch>|direct user approval|must not be approved by auto-review' codex/.codex/AGENTS.md
```

Expected: output includes the updated sensitive operations bullet.

## Task 3: Add Focused Sync-Test Assertions

**Files:**
- Modify: `codex/.codex/tests/test-codex-sync-hooks.sh`

- [ ] **Step 1: Locate the existing generated-config assertions**

Run:

```bash
sed -n '104,118p' codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: output includes:

```bash
assert_table_contains "$CONFIG" '[auto_review]' 'Approve routine sandbox-compatible repository work'
```

- [ ] **Step 2: Add assertions for merge-to-main policy phrases**

Immediately after the existing auto-review assertion, add:

```bash
assert_table_contains "$CONFIG" '[auto_review]' 'gh pr merge'
assert_table_contains "$CONFIG" '[auto_review]' 'local merge-to-main operations'
assert_table_contains "$CONFIG" '[auto_review]' 'git checkout main followed by git merge <branch>'
assert_table_contains "$CONFIG" '[auto_review]' 'These sensitive operations require direct user approval'
```

This verifies the checked-in base config survives `codex-sync` into the generated local config.

## Task 4: Regenerate and Verify

**Files:**
- Read/execute: `bin/.local/bin/codex-sync`
- Generated local-only: `codex/.codex/config.toml`

- [ ] **Step 1: Run the Codex sync test**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: command exits 0.

- [ ] **Step 2: Regenerate the local config in the worktree**

Run:

```bash
DOTFILES="$PWD" bash bin/.local/bin/codex-sync
```

Expected: command exits 0. If run from a linked worktree, it may generate worktree-local config without live wiring; that is acceptable.

- [ ] **Step 3: Verify generated config includes the merge-to-main phrases**

Run:

```bash
rg -n 'gh pr merge|local merge-to-main|git checkout main|git merge <branch>|direct user approval' codex/.codex/config.toml
```

Expected: output includes the new phrases.

- [ ] **Step 4: Confirm generated config is not staged**

Run:

```bash
git status --short --ignored codex/.codex/config.toml
```

Expected: output is either `!! codex/.codex/config.toml` or no tracked modification. Do not force-add `codex/.codex/config.toml`.

## Task 5: Commit the Implementation

**Files:**
- Commit: `codex/.codex/config.base.toml`
- Commit: `codex/.codex/AGENTS.md`
- Commit: `codex/.codex/tests/test-codex-sync-hooks.sh`
- Do not commit: `codex/.codex/config.toml`

- [ ] **Step 1: Review the diff**

Run:

```bash
git diff -- codex/.codex/config.base.toml codex/.codex/AGENTS.md codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: diff only updates approval wording and focused sync-test assertions.

- [ ] **Step 2: Commit the implementation**

Run:

```bash
git add codex/.codex/config.base.toml codex/.codex/AGENTS.md codex/.codex/tests/test-codex-sync-hooks.sh
git commit -m "fix(codex): require approval for merges to main"
```

Expected: commit succeeds with only the three implementation files staged.
