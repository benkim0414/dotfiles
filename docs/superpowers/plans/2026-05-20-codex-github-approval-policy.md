# Codex GitHub Approval Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Codex auto-review approve routine GitHub PR, issue, fetch, pull, and ordinary push operations from a linked worktree while preserving direct approval for merge, destructive, credential, history rewrite, and broad network operations.

**Architecture:** Keep `codex/.codex/config.base.toml` as the durable Codex config source and regenerate the ignored `codex/.codex/config.toml` with `bin/.local/bin/codex-sync` during verification. Mirror the same approval contract in `codex/.codex/AGENTS.md` so agents and subagents receive consistent behavioral instructions.

**Tech Stack:** Codex TOML config, Markdown instructions, Bash verification with `rg`, existing `bin/.local/bin/codex-sync`.

---

## File Structure

- Modify: `codex/.codex/config.base.toml`
  - Responsibility: durable source for the Codex auto-review policy.
- Generated local-only: `codex/.codex/config.toml`
  - Responsibility: active local Codex config copied from `config.base.toml` by `bin/.local/bin/codex-sync`; verify it, but do not commit it if ignored.
- Modify: `codex/.codex/AGENTS.md`
  - Responsibility: human-readable and agent-readable approval contract inherited by Codex sessions.
- Read-only: `bin/.local/bin/codex-sync`
  - Responsibility: existing config regeneration helper.
- Verify: `docs/superpowers/specs/2026-05-20-codex-github-approval-policy-design.md`
  - Responsibility: approved design source for this implementation.

### Task 1: Update Auto-Review Policy

**Files:**
- Modify: `codex/.codex/config.base.toml`
- Generated local-only: `codex/.codex/config.toml`

- [ ] **Step 1: Inspect the current auto-review policy**

Run:

```bash
sed -n '/^\[auto_review\]/,/^\[features\]/p' codex/.codex/config.base.toml
```

Expected: output includes a policy that approves routine sandbox-compatible repository work and denies all network access.

- [ ] **Step 2: Replace the policy text**

In `codex/.codex/config.base.toml`, replace only the text inside `[auto_review].policy` with:

```toml
policy = """
Approve routine sandbox-compatible repository work: read-only commands, status
inspection, diffs, formatting checks, and test commands that write only inside
the active workspace or temporary directories.

Approve GitHub-scoped collaboration and branch sync commands when they are run
from the active repository worktree and are limited to ordinary PR, issue,
fetch, pull, or push workflows. This includes GitHub CLI PR and issue view,
list, create, edit, comment, check, status, and review operations; git fetch;
git pull; and ordinary git push to GitHub remotes.

Deny destructive commands, broad arbitrary shell approvals, credential access,
writes outside configured workspace roots, non-GitHub network access, direct
GitHub API access through arbitrary runtimes or shell scripts, GitHub merge
operations, branch deletion, repository administration, settings or secrets
changes, destructive issue or PR operations, force pushes, history rewrites,
and broad branch mutation commands. These sensitive operations require direct
user approval and must not be approved by auto-review.

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

- [ ] **Step 3: Verify required allow and deny phrases are present**

Run:

```bash
rg -n 'GitHub-scoped|gh pr|gh issue|git fetch|git pull|git push|GitHub merge|force pushes|non-GitHub network|credential access' codex/.codex/config.base.toml
```

Expected: output includes matches for the new GitHub allowance, the narrow prefix examples, and the deny list.

- [ ] **Step 4: Regenerate local Codex config**

Run:

```bash
DOTFILES="$PWD" bash bin/.local/bin/codex-sync
```

Expected: command exits 0. In a non-primary worktree it may print the existing message about generated config only and `CODEX_SYNC_LIVE=1`; that is acceptable if `codex/.codex/config.toml` is generated.

- [ ] **Step 5: Verify generated config mirrors the base policy**

Run:

```bash
rg -n 'GitHub-scoped|gh pr|gh issue|git fetch|git pull|git push|GitHub merge|force pushes|non-GitHub network|credential access' codex/.codex/config.toml
```

Expected: output includes the same policy phrases as `config.base.toml`.

- [ ] **Step 6: Confirm generated config is not accidentally staged**

Run:

```bash
git status --short --ignored codex/.codex/config.toml
```

Expected: output is either `!! codex/.codex/config.toml` or no tracked modification. Do not force-add `codex/.codex/config.toml`.

- [ ] **Step 7: Commit the base config policy update**

Run:

```bash
git add codex/.codex/config.base.toml
git diff --cached -- codex/.codex/config.base.toml
git commit -m "fix(codex): allow routine GitHub approvals"
```

Expected: commit succeeds with only `codex/.codex/config.base.toml` staged.

### Task 2: Update Agent Approval Instructions

**Files:**
- Modify: `codex/.codex/AGENTS.md`

- [ ] **Step 1: Inspect the current approval contract**

Run:

```bash
sed -n '1,18p' codex/.codex/AGENTS.md
```

Expected: output includes the existing "Subagent Approval Contract" section.

- [ ] **Step 2: Replace the sensitive operations bullets**

In `codex/.codex/AGENTS.md`, replace the three bullets under "Subagent Approval Contract" that currently describe routine work, sensitive operations, and persistent prefix rules with:

```markdown
- Routine sandbox-compatible repository work should flow through the configured auto reviewer.
- GitHub-scoped collaboration and branch sync operations may flow through auto-review when issued from an active repository worktree: `gh pr view/list/create/edit/comment/check/status/review`, `gh issue view/list/create/edit/comment/status`, `git fetch`, `git pull`, and ordinary `git push` to GitHub remotes.
- Sensitive operations require direct user approval and must not be approved by auto-review: `gh pr merge`, branch deletion, repository administration, settings or secrets changes, destructive issue or PR operations, force pushes, history rewrites, credential access, non-GitHub network access, direct GitHub API access through arbitrary runtimes or shell scripts, destructive commands, and writes outside configured workspace roots.
- Persistent prefix rules must be narrow and command-specific, with operation-specific examples such as `gh pr view`, `gh pr list`, `gh pr create`, `gh pr edit`, `gh pr comment`, `gh pr check`, `gh pr status`, `gh pr review`, `gh issue view`, `gh issue list`, `gh issue create`, `gh issue edit`, `gh issue comment`, and `gh issue status`.
- Under the current prefix-rule model, git network commands (`git fetch`, `git pull`, `git push`) should use per-command approval unless the approval mechanism can enforce the exact GitHub, active-worktree, and non-destructive constraints.
- Do not persist broad runtime prefixes such as `bash`, `python`, `node`, `ruby`, `perl`, or `sh`.
```

- [ ] **Step 3: Verify AGENTS wording includes the policy boundaries**

Run:

```bash
rg -n 'GitHub-scoped|gh pr|gh issue|git fetch|git pull|git push|gh pr merge|force pushes|non-GitHub network|credential access' codex/.codex/AGENTS.md
```

Expected: output includes the GitHub allowance and the high-risk denials.

- [ ] **Step 4: Commit the instruction update**

Run:

```bash
git add codex/.codex/AGENTS.md
git diff --cached -- codex/.codex/AGENTS.md
git commit -m "docs(codex): document GitHub approval boundaries"
```

Expected: commit succeeds with only `codex/.codex/AGENTS.md` staged.

### Task 3: Final Verification

**Files:**
- Verify: `codex/.codex/config.base.toml`
- Verify: `codex/.codex/config.toml`
- Verify: `codex/.codex/AGENTS.md`
- Verify: `docs/superpowers/specs/2026-05-20-codex-github-approval-policy-design.md`

- [ ] **Step 1: Confirm implementation covers the approved spec**

Run:

```bash
rg -n 'GitHub-scoped|gh pr|gh issue|git fetch|git pull|git push|gh pr merge|force pushes|history rewrites|credential access|non-GitHub network access|writes outside configured workspace roots' codex/.codex/config.base.toml codex/.codex/config.toml codex/.codex/AGENTS.md
```

Expected: each file has matches for the GitHub allowance and the deny boundaries.

- [ ] **Step 2: Confirm global sandbox settings remain unchanged**

Run:

```bash
rg -n '^sandbox_mode = "workspace-write"$|^approval_policy = "on-request"$|^approvals_reviewer = "auto_review"$' codex/.codex/config.base.toml codex/.codex/config.toml
```

Expected: both config files still contain `sandbox_mode = "workspace-write"`, `approval_policy = "on-request"`, and `approvals_reviewer = "auto_review"`.

- [ ] **Step 3: Run sync hook regression test**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: command exits 0 and prints `ok codex sync hook wiring`.

- [ ] **Step 4: Inspect final diff and status**

Run:

```bash
git status --short
git log --oneline -3
```

Expected: working tree is clean except for intentionally untracked or ignored generated files. Recent commits include the design spec commit and the two implementation commits.
