# Allow Primary Checkout Git Pull Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow safe `git pull` commands in the primary checkout while keeping the worktree guard strict for broader primary-checkout writes.

**Architecture:** Add focused regression cases to `test-worktree-guard-hook.sh`, then implement a narrow `git pull` allow helper in `worktree-guard.sh`. The helper treats pull as a constrained sync operation, not as read-only behavior.

**Tech Stack:** Bash, Git, jq, existing Codex PreToolUse hook test harness.

---

## File Structure

- Modify `codex/.codex/tests/test-worktree-guard-hook.sh`
  - Adds allow/deny coverage for primary-checkout `git pull` variants.
  - Reuses existing `assert_allowed_command` and `assert_approval_required_command` helpers.
- Modify `codex/.codex/hooks/worktree-guard.sh`
  - Adds `is_allowed_primary_checkout_pull_command`.
  - Wires the helper into shell and MCP executor paths before the generic primary-worktree approval requirement.

## Task 1: Add Failing Pull Policy Tests

**Files:**
- Modify: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Add primary-checkout pull test cases**

Insert this block after the existing read-only git assertions:

```bash
assert_allowed_command "$PRIMARY_REPO" "git status --short"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO status --short"
assert_allowed_command "$PRIMARY_REPO" "git diff -- README.md"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO diff -- README.md"
assert_allowed_command "$PRIMARY_REPO" "git ls-files"
assert_allowed_command "$PRIMARY_REPO" "git branch --show-current"
assert_allowed_command "$PRIMARY_REPO" "git -C $PRIMARY_REPO branch --show-current"
```

Add this new block immediately after it:

```bash
assert_allowed_command "$PRIMARY_REPO" "git pull"
assert_allowed_command "$PRIMARY_REPO" "git pull --ff-only"
assert_allowed_command "$PRIMARY_REPO" "git pull --rebase"
assert_allowed_command "$PRIMARY_REPO" "git pull origin"
assert_allowed_command "$PRIMARY_REPO" "git pull origin main"
assert_allowed_command "$PRIMARY_REPO" "git pull --ff-only origin main"
assert_allowed_command "$PRIMARY_REPO" "git pull --rebase origin main"
assert_allowed_command "$OUTSIDE_DIR" "git -C $PRIMARY_REPO pull --ff-only"
assert_approval_required_command "$PRIMARY_REPO" "git pull origin feature" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull upstream main" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --all" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --tags" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --force" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull origin main extra" "primary worktree"
assert_approval_required_command "$PRIMARY_REPO" "git pull --ff-only; touch generated.txt" "primary worktree"
```

- [ ] **Step 2: Run the hook test and verify the new tests fail**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected before implementation:

```text
expected allowed but denied: git pull in <fixture-primary-repo>
```

- [ ] **Step 3: Commit the failing tests**

Run:

```bash
git add codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "test(codex): cover primary checkout git pull policy"
```

## Task 2: Allow Narrow Primary Checkout Git Pull Forms

**Files:**
- Modify: `codex/.codex/hooks/worktree-guard.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Add the narrow pull helper**

Add this helper after `git_words_have_force_flag`:

```bash
is_allowed_primary_checkout_pull_command() {
  local command="$1"
  local base_dir="${2:-$cwd}"
  local -a pull_words
  local active_branch
  local saw_ff_only=0
  local saw_rebase=0
  local remote=""
  local branch=""
  local i
  local word

  is_linked_worktree "$base_dir" && return 1
  has_shell_control_syntax "$command" && return 1
  has_shell_path_indirection "$command" && return 1

  git_lifecycle_words "$command" pull_words || return 1
  [[ "${pull_words[1]:-}" == "pull" ]] || return 1

  active_branch="$(active_branch_for "$base_dir")"
  [[ -n "$active_branch" ]] || return 1

  i=2
  while (( i < ${#pull_words[@]} )); do
    word="${pull_words[i]}"
    case "$word" in
      --ff-only)
        saw_ff_only=1
        ;;
      --rebase)
        saw_rebase=1
        ;;
      --force|-f|--all|--tags|--prune)
        return 1
        ;;
      --)
        return 1
        ;;
      -*)
        return 1
        ;;
      *)
        if [[ -z "$remote" ]]; then
          remote="$word"
        elif [[ -z "$branch" ]]; then
          branch="$word"
        else
          return 1
        fi
        ;;
    esac
    i=$((i + 1))
  done

  [[ "$saw_ff_only" -eq 1 && "$saw_rebase" -eq 1 ]] && return 1
  [[ -z "$remote" || "$remote" == "origin" ]] || return 1
  [[ -z "$branch" || "$branch" == "$active_branch" ]] || return 1

  return 0
}
```

- [ ] **Step 2: Allow the helper in the shell-tool path**

In the `if is_shell_tool; then` block, find:

```bash
  if is_allowed_worktree_lifecycle_git_command "$command" "$command_cwd"; then
    exit 0
  fi
```

Change it to:

```bash
  if is_allowed_worktree_lifecycle_git_command "$command" "$command_cwd"; then
    exit 0
  fi

  if is_allowed_primary_checkout_pull_command "$command" "$command_cwd"; then
    exit 0
  fi
```

- [ ] **Step 3: Allow the helper in the MCP executor path**

In the `if is_mcp_executor_tool; then` loop, find:

```bash
    if is_allowed_worktree_lifecycle_git_command "$command" "$command_cwd"; then
      continue
    fi
```

Change it to:

```bash
    if is_allowed_worktree_lifecycle_git_command "$command" "$command_cwd"; then
      continue
    fi

    if is_allowed_primary_checkout_pull_command "$command" "$command_cwd"; then
      continue
    fi
```

- [ ] **Step 4: Run the hook test and verify it passes**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected:

```text
ok worktree guard hook
```

- [ ] **Step 5: Commit the implementation**

Run:

```bash
git add codex/.codex/hooks/worktree-guard.sh codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "fix(codex): allow safe primary checkout git pull"
```

## Final Verification

- [ ] **Step 1: Run the focused hook suite**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected:

```text
ok worktree guard hook
```

- [ ] **Step 2: Confirm no uncommitted implementation changes remain**

Run:

```bash
git status --short --branch
```

Expected:

```text
## allow-primary-git-pull
```
