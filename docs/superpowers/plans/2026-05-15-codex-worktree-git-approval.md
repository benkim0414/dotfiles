# Codex Worktree Git Approval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Codex run otherwise valid Git commands without approval in linked Git worktrees while keeping atomic commit enforcement active everywhere.

**Architecture:** Keep `atomic-commits.sh` responsible for blocking broad staging and commit-all commands. Add linked-worktree detection based on Git metadata, then add approval-bypass behavior only if Codex supports an explicit hook allow decision; otherwise document the limitation without weakening global approval settings.

**Tech Stack:** Codex CLI config and hooks, Bash, `jq`, Git worktrees, GNU Stow dotfiles layout.

---

## Source Material

- Design spec: `docs/superpowers/specs/2026-05-15-codex-worktree-git-approval-design.md`
- Existing hook: `codex/.codex/hooks/atomic-commits.sh`
- Existing tests: `codex/.codex/tests/test-atomic-commits-hook.sh`
- Existing config: `codex/.codex/config.base.toml`
- Official Codex config schema: `https://developers.openai.com/codex/config-schema.json`

## File Structure

- Modify `codex/.codex/hooks/atomic-commits.sh`
  - Parse hook `cwd` and run worktree detection relative to it.
  - Preserve all existing deny behavior.
  - Add an `allow` output only if Task 1 verifies Codex supports it.
- Modify `codex/.codex/tests/test-atomic-commits-hook.sh`
  - Add fixture helpers for a temporary primary checkout and linked worktree.
  - Add tests that broad staging remains denied in both primary and linked worktrees.
  - Add tests for linked-worktree approval output only if Task 1 verifies support.
- Modify `docs/superpowers/specs/2026-05-15-codex-worktree-git-approval-design.md`
  - Only if Task 1 proves Codex cannot express a scoped approval bypass.
  - Record the limitation and keep enforcement unchanged.
- Do not modify `codex/.codex/config.base.toml`; the current schema does not expose a verified worktree-scoped command approval rule.

## Task 1: Verify Codex Approval Mechanism

**Files:**
- Read: `codex/.codex/config.base.toml`
- Read: official schema from `https://developers.openai.com/codex/config-schema.json`
- Optional Modify: `docs/superpowers/specs/2026-05-15-codex-worktree-git-approval-design.md`

- [x] **Step 1: Search local config and hooks for allow examples**

Run:

```bash
rg -n 'permissionDecision.*allow|approval_policy|GranularApprovalConfig|request_rule|exec_permission_approvals' codex/.codex docs/superpowers claude/.claude -g '*.toml' -g '*.md' -g '*.sh'
```

Expected: local examples show `permissionDecision = "deny"` only, plus current `approval_policy = "on-request"`.

- [x] **Step 2: Check the official Codex schema for approval rule support**

Run:

```bash
curl -fsSL https://developers.openai.com/codex/config-schema.json \
  | jq '.definitions.AskForApproval, .definitions.GranularApprovalConfig, .definitions.HooksToml, .definitions.MatcherGroup'
```

Expected: schema output describes approval policy, granular approval categories, and hook configuration. Do not add config-based approval rules, because the current schema does not expose a verified command-pattern plus linked-worktree condition.

- [x] **Step 3: Search official schema for hook permission decision values**

Run:

```bash
curl -fsSL https://developers.openai.com/codex/config-schema.json \
  | rg -n 'permissionDecision|approve|allow|deny|hooks|PreToolUse'
```

Expected: if `permissionDecision` values are not described by the schema, treat explicit hook allow support as unverified until manually tested in the Codex CLI.

- [x] **Step 4: Decide implementation path**

Use these exact criteria:

```text
If Codex hook output supports permissionDecision "allow" for PreToolUse:
  Implement Tasks 2, 3A, 4, 5, and 6.

If Codex hook output does not support permissionDecision "allow" for PreToolUse:
  Implement Tasks 2, 3C, 5, and 6. Do not weaken approval_policy or sandbox_mode.
```

## Task 2: Add Worktree Fixture Tests Without Changing Hook Behavior

**Files:**
- Modify: `codex/.codex/tests/test-atomic-commits-hook.sh`
- Test: `codex/.codex/tests/test-atomic-commits-hook.sh`

- [x] **Step 1: Add test fixture helpers**

Edit `codex/.codex/tests/test-atomic-commits-hook.sh`. Replace the single-line hook definition:

```bash
HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"; HOOK="$HOOK_ROOT/atomic-commits.sh"
```

with:

```bash
HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
HOOK="$HOOK_ROOT/atomic-commits.sh"
TEST_ROOT=""
PRIMARY_REPO=""
LINKED_WORKTREE=""

cleanup() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    rm -rf "$TEST_ROOT"
  fi
}

trap cleanup EXIT

setup_git_fixture() {
  TEST_ROOT="$(mktemp -d)"
  PRIMARY_REPO="$TEST_ROOT/primary"
  LINKED_WORKTREE="$TEST_ROOT/linked"

  git init "$PRIMARY_REPO" >/dev/null
  git -C "$PRIMARY_REPO" config user.email "codex@example.test"
  git -C "$PRIMARY_REPO" config user.name "Codex Test"
  printf 'fixture\n' >"$PRIMARY_REPO/README.md"
  git -C "$PRIMARY_REPO" add README.md
  git -C "$PRIMARY_REPO" commit -m "test: seed fixture" >/dev/null
  git -C "$PRIMARY_REPO" worktree add "$LINKED_WORKTREE" -b fixture-worktree >/dev/null
}
```

- [x] **Step 2: Add cwd-aware hook runner**

After the existing `run_hook()` function, add:

```bash
run_hook_in_dir() {
  local cwd="$1"
  local cmd="$2"

  (
    cd "$cwd"
    jq -cn --arg cmd "$cmd" --arg cwd "$PWD" '{
      hook_event_name: "PreToolUse",
      tool_name: "Bash",
      cwd: $cwd,
      tool_input: {
        command: $cmd
      }
    }' | bash "$HOOK"
  )
}
```

- [x] **Step 3: Add assertion helpers for fixture directories**

After `assert_allowed()`, add:

```bash
assert_denied_in_dir() {
  local cwd="$1"
  local cmd="$2"
  local output

  output="$(run_hook_in_dir "$cwd" "$cmd")"
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"
  echo "ok denied in $cwd: $cmd"
}

assert_allowed_in_dir() {
  local cwd="$1"
  local cmd="$2"
  local output

  output="$(run_hook_in_dir "$cwd" "$cmd")"
  if [[ -n "$output" ]] && jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    echo "expected allowed in $cwd but denied: $cmd" >&2
    echo "$output" >&2
    return 1
  fi
  echo "ok allowed in $cwd: $cmd"
}
```

- [x] **Step 4: Add primary and linked-worktree atomic enforcement tests**

At the end of the file, add:

```bash
setup_git_fixture

assert_denied_in_dir "$PRIMARY_REPO" "git add ."
assert_denied_in_dir "$PRIMARY_REPO" "git add -A"
assert_denied_in_dir "$PRIMARY_REPO" "git add -u"
assert_denied_in_dir "$PRIMARY_REPO" "git commit -am 'fix(test): change'"
assert_allowed_in_dir "$PRIMARY_REPO" "git add README.md"
assert_allowed_in_dir "$PRIMARY_REPO" "git commit -m 'fix(test): change'"

assert_denied_in_dir "$LINKED_WORKTREE" "git add ."
assert_denied_in_dir "$LINKED_WORKTREE" "git add -A"
assert_denied_in_dir "$LINKED_WORKTREE" "git add -u"
assert_denied_in_dir "$LINKED_WORKTREE" "git commit -am 'fix(test): change'"
assert_allowed_in_dir "$LINKED_WORKTREE" "git add README.md"
assert_allowed_in_dir "$LINKED_WORKTREE" "git commit -m 'fix(test): change'"
```

- [x] **Step 5: Run tests and verify they pass before behavior changes**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: PASS. The new tests only prove the current atomic convention remains active in both primary and linked worktree checkouts.

- [x] **Step 6: Commit fixture test coverage**

Run:

```bash
git add codex/.codex/tests/test-atomic-commits-hook.sh
git commit -m "test(codex): cover worktree atomic enforcement"
```

Expected: commit succeeds.

## Task 3A: Add Hook-Based Worktree Approval Output

Use this task only if Task 1 verifies Codex supports `permissionDecision = "allow"` from `PreToolUse` hook output.

Execution note: skipped. Task 1 did not verify hook-based `permissionDecision = "allow"` support.

**Files:**
- Modify: `codex/.codex/hooks/atomic-commits.sh`
- Modify: `codex/.codex/tests/test-atomic-commits-hook.sh`
- Test: `codex/.codex/tests/test-atomic-commits-hook.sh`

- [ ] **Step 1: Add explicit allow assertion helper**

In `codex/.codex/tests/test-atomic-commits-hook.sh`, after `assert_allowed_in_dir()`, add:

```bash
assert_explicitly_allowed_in_dir() {
  local cwd="$1"
  local cmd="$2"
  local output

  output="$(run_hook_in_dir "$cwd" "$cmd")"
  jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null <<<"$output"
  echo "ok explicitly allowed in $cwd: $cmd"
}
```

- [ ] **Step 2: Add failing linked-worktree allow tests**

At the end of `codex/.codex/tests/test-atomic-commits-hook.sh`, add:

```bash
assert_explicitly_allowed_in_dir "$LINKED_WORKTREE" "git status --short"
assert_explicitly_allowed_in_dir "$LINKED_WORKTREE" "git add README.md"
assert_explicitly_allowed_in_dir "$LINKED_WORKTREE" "git branch"
assert_explicitly_allowed_in_dir "$LINKED_WORKTREE" "git stash list"
```

- [ ] **Step 3: Run tests and verify the new allow tests fail**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: FAIL at the first `assert_explicitly_allowed_in_dir` because the hook currently emits no explicit allow output.

- [ ] **Step 4: Add cwd, allow, and linked-worktree helpers to the hook**

In `codex/.codex/hooks/atomic-commits.sh`, after the `command_text` assignment, add:

```bash
hook_cwd="$(jq -r '.cwd // ""' <<<"$input")"

if [[ -n "$hook_cwd" && -d "$hook_cwd" ]]; then
  cd "$hook_cwd" 2>/dev/null || true
fi
```

After `deny()`, add:

```bash
allow() {
  local reason="$1"

  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

is_linked_git_worktree() {
  local git_abs_dir
  local git_common_dir
  local superproject

  git rev-parse --git-dir >/dev/null 2>&1 || return 1

  if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
    return 1
  fi

  superproject="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -n "$superproject" ]]; then
    return 1
  fi

  git_abs_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1

  git_abs_dir="$(cd "$git_abs_dir" 2>/dev/null && pwd -P)" || return 1
  git_common_dir="$(cd "$git_common_dir" 2>/dev/null && pwd -P)" || return 1

  [[ "$git_abs_dir" != "$git_common_dir" ]]
}

command_contains_git() {
  [[ "$command_text" =~ (^|[[:space:];|&(){}])git([[:space:]]|$) ]]
}
```

- [ ] **Step 5: Emit explicit allow only after deny scanning completes**

At the very end of `codex/.codex/hooks/atomic-commits.sh`, replace:

```bash
scan_shell_commands "$command_text"
```

with:

```bash
scan_shell_commands "$command_text"

if command_contains_git && is_linked_git_worktree; then
  allow "Git command allowed without approval inside linked worktree; atomic commit guard passed."
fi
```

- [ ] **Step 6: Run tests and verify all hook behavior passes**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: PASS. Broad staging and commit-all commands remain denied in the linked worktree; valid Git commands in the linked worktree emit `permissionDecision = "allow"`.

- [ ] **Step 7: Commit hook-based approval behavior**

Run:

```bash
git add codex/.codex/hooks/atomic-commits.sh codex/.codex/tests/test-atomic-commits-hook.sh
git commit -m "feat(codex): allow valid git in worktrees"
```

Expected: commit succeeds.

## Task 3C: Document Unsupported Scoped Approval

Use this task only if Task 1 verifies neither hooks nor config can express "allow Git without approval only in linked worktrees."

**Files:**
- Modify: `docs/superpowers/specs/2026-05-15-codex-worktree-git-approval-design.md`

- [x] **Step 1: Replace the implementation constraint with the verified limitation**

In `docs/superpowers/specs/2026-05-15-codex-worktree-git-approval-design.md`, replace the `## Implementation Constraint` section with:

```markdown
## Verified Codex Limitation

Codex currently exposes the local policy needed to deny unsafe commands, but this
setup does not have a verified way to express "allow Git commands without
approval only when the current checkout is a linked Git worktree." The config
schema supports broad approval modes and granular approval categories, but no
verified command-pattern plus worktree-scoped rule. The local hook examples only
use `permissionDecision = "deny"`.

Because the scoped approval bypass cannot be expressed safely, implementation
must keep `approval_policy = "on-request"` unchanged and preserve the atomic
commit hook unchanged except for test coverage. Do not replace this with
`approval_policy = "never"` or a global Git allow rule.
```

- [x] **Step 2: Commit the limitation update**

Run:

```bash
git add docs/superpowers/specs/2026-05-15-codex-worktree-git-approval-design.md
git commit -m "docs(codex): record worktree approval limitation"
```

Expected: commit succeeds.

## Task 4: Validate Real Codex Behavior

Skip this task if Task 3C was used.

Execution note: skipped because Task 3C was used.

**Files:**
- Read: `codex/.codex/config.base.toml`
- Read: `codex/.codex/hooks/atomic-commits.sh`
- Generated local-only: `codex/.codex/config.toml`

- [ ] **Step 1: Sync Codex config**

Run:

```bash
codex-sync
```

Expected: `codex/.codex/config.toml` is regenerated locally and remains untracked.

- [ ] **Step 2: Verify linked-worktree detection from this worktree**

Run:

```bash
git_dir="$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P)"
git_common="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
printf 'git_dir=%s\ngit_common=%s\nlinked=%s\n' "$git_dir" "$git_common" "$([[ "$git_dir" != "$git_common" ]] && echo yes || echo no)"
```

Expected: output includes `linked=yes`.

- [ ] **Step 3: Verify the hook denies broad staging from the linked worktree**

Run:

```bash
jq -cn --arg cmd 'git add .' --arg cwd "$PWD" '{
  hook_event_name: "PreToolUse",
  tool_name: "Bash",
  cwd: $cwd,
  tool_input: { command: $cmd }
}' | bash codex/.codex/hooks/atomic-commits.sh | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
```

Expected: command exits `0`, proving `git add .` is still denied in the linked worktree.

- [ ] **Step 4: Verify the hook approval output for a valid Git command**

Run this only for Task 3A:

```bash
jq -cn --arg cmd 'git status --short' --arg cwd "$PWD" '{
  hook_event_name: "PreToolUse",
  tool_name: "Bash",
  cwd: $cwd,
  tool_input: { command: $cmd }
}' | bash codex/.codex/hooks/atomic-commits.sh | jq -e '.hookSpecificOutput.permissionDecision == "allow"'
```

Expected: command exits `0`, proving the hook emits explicit allow output for a valid Git command in a linked worktree.

- [ ] **Step 5: Verify non-Git commands are not explicitly approved**

Run this only for Task 3A:

```bash
output="$(jq -cn --arg cmd 'sed -n "1,20p" README.md' --arg cwd "$PWD" '{
  hook_event_name: "PreToolUse",
  tool_name: "Bash",
  cwd: $cwd,
  tool_input: { command: $cmd }
}' | bash codex/.codex/hooks/atomic-commits.sh)"
[[ -z "$output" ]]
```

Expected: command exits `0`, proving the hook does not emit approval output for non-Git commands.

## Task 5: Full Regression Verification

**Files:**
- Test: `codex/.codex/tests/test-atomic-commits-hook.sh`
- Read: changed files from previous tasks

- [x] **Step 1: Run hook regression tests**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: PASS.

- [x] **Step 2: Inspect tracked changes**

Run:

```bash
git status --short
git diff --stat
```

Expected: only files intentionally changed by the selected tasks appear.

- [x] **Step 3: Inspect staged and unstaged diffs before final commit**

Run:

```bash
git diff
git diff --cached
```

Expected: diffs match the selected implementation path and contain no generated `codex/.codex/config.toml` changes.

## Task 6: Final Documentation and Commit

**Files:**
- Modify: `docs/superpowers/plans/2026-05-15-codex-worktree-git-approval.md`
- Optional Modify: `docs/superpowers/specs/2026-05-15-codex-worktree-git-approval-design.md`

- [x] **Step 1: Mark completed plan tasks**

Update checkbox statuses in this plan for the tasks executed. Leave tasks from the unselected path unchecked.

- [ ] **Step 2: Commit the plan execution updates**

Run:

```bash
git add docs/superpowers/plans/2026-05-15-codex-worktree-git-approval.md
git commit -m "docs(codex): plan worktree git approval"
```

Expected: commit succeeds.

- [ ] **Step 3: Report final branch state**

Run:

```bash
git log --oneline main..HEAD
git status --short
```

Expected: `git status --short` is empty. The log lists the plan commit plus any implementation commits from the selected path.
