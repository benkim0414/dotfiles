# Codex Worktree Guard Effective Cwd Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Codex worktree guard so legitimate writes in linked worktrees and non-repo scratch directories are allowed even when the hook session cwd points at a repository's main worktree.

**Architecture:** Keep one focused Bash hook as the enforcement boundary. Add test coverage for effective shell workdir fields, explicit `git -C` targets, and `/tmp` scratch writes before changing the guard. The hook should prefer the effective command directory when present, classify `git -C` commands by the selected checkout, and continue denying writes into main worktrees.

**Tech Stack:** Bash, jq, Git worktrees, Codex PreToolUse hook payloads, shell tests.

---

## File Structure

- Modify: `codex/.codex/hooks/worktree-guard.sh`
  - Owns worktree isolation checks for Codex PreToolUse events.
  - Add helpers for effective tool cwd and `git -C` path extraction.
  - Keep main-worktree denial behavior local to this script.
- Modify: `codex/.codex/tests/test-worktree-guard-hook.sh`
  - Adds regression coverage for the reported staging blocker and scratch write false positive.
- No config change is expected because the hook path and registration stay unchanged.

### Task 1: Add Failing Regression Tests

**Files:**
- Modify: `codex/.codex/tests/test-worktree-guard-hook.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Add a helper that can include an effective workdir field**

In `codex/.codex/tests/test-worktree-guard-hook.sh`, add this helper after `run_hook_json()`:

```bash
run_hook_json_with_tool_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local tool_name="$3"
  local tool_input="$4"

  jq -cn \
    --arg cwd "$cwd" \
    --arg tool_workdir "$tool_workdir" \
    --arg tool_name "$tool_name" \
    --argjson tool_input "$tool_input" '{
      hook_event_name: "PreToolUse",
      tool_name: $tool_name,
      cwd: $cwd,
      tool_input: ($tool_input + {workdir: $tool_workdir})
    }' | bash "$HOOK"
}
```

- [ ] **Step 2: Add an assertion helper for effective workdir shell commands**

In the same file, add this helper after `assert_allowed_json()`:

```bash
assert_allowed_command_with_tool_workdir() {
  local cwd="$1"
  local tool_workdir="$2"
  local command="$3"
  local output

  output="$(run_hook_json_with_tool_workdir "$cwd" "$tool_workdir" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')")"
  if [[ -n "$output" ]]; then
    jq -e . >/dev/null <<<"$output"
    if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
      echo "expected allowed but denied: $command with workdir=$tool_workdir and cwd=$cwd" >&2
      echo "$output" >&2
      return 1
    fi
  fi
  echo "ok allowed $command with workdir=$tool_workdir and cwd=$cwd"
}
```

- [ ] **Step 3: Add failing regression cases**

After the existing linked-worktree `Write` allow assertion, add:

```bash
assert_allowed_command_with_tool_workdir "$PRIMARY_REPO" "$LINKED_WORKTREE" "git add README.md"
assert_allowed_command "$PRIMARY_REPO" "git -C $LINKED_WORKTREE add README.md"
assert_denied_command "$LINKED_WORKTREE" "git -C $PRIMARY_REPO add README.md"
assert_allowed_command "$PRIMARY_REPO" "touch /tmp/worktree-guard-scratch-$$"
```

- [ ] **Step 4: Run the test and confirm the regression is reproduced**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: FAIL before the implementation change. The output should show at least one denied command that should be allowed, such as `git add README.md` with `workdir=$LINKED_WORKTREE`, `git -C $LINKED_WORKTREE add README.md`, or `touch /tmp/worktree-guard-scratch-...`.

- [ ] **Step 5: Commit the failing tests**

Run:

```bash
git add codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "test(codex): cover worktree guard cwd regressions"
```

### Task 2: Respect Effective Shell Workdir and Explicit Git -C Targets

**Files:**
- Modify: `codex/.codex/hooks/worktree-guard.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Add an effective cwd helper**

In `codex/.codex/hooks/worktree-guard.sh`, add this function after the initial `cwd` fallback block:

```bash
effective_cwd() {
  local candidate

  candidate="$(jq -r '
    .tool_input.workdir //
    .tool_input.cwd //
    .tool_input.current_working_directory //
    empty
  ' <<<"$input" 2>/dev/null || true)"

  if [[ -n "$candidate" && -d "$candidate" ]]; then
    canonical_path "$candidate"
    return
  fi

  canonical_path "$cwd"
}
```

- [ ] **Step 2: Pass the selected directory into repo helpers**

Change the existing helpers so they accept an optional directory argument and default to `cwd`:

```bash
repo_root_for() {
  local dir="${1:-$cwd}"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
}
```

```bash
is_linked_worktree() {
  local dir="${1:-$cwd}"
  local absolute_git_dir
  local common_git_dir

  absolute_git_dir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null || true)"
  common_git_dir="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || true)"

  if [[ -z "$absolute_git_dir" || -z "$common_git_dir" ]]; then
    return 1
  fi

  absolute_git_dir="$(canonical_path "$absolute_git_dir")"
  if [[ "$common_git_dir" = /* ]]; then
    common_git_dir="$(canonical_path "$common_git_dir")"
  else
    common_git_dir="$(canonical_path "$dir/$common_git_dir")"
  fi

  [[ "$absolute_git_dir" != "$common_git_dir" ]]
}
```

```bash
primary_worktree_root_for_current_repo() {
  local dir="${1:-$cwd}"
  local common_git_dir

  common_git_dir="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -z "$common_git_dir" ]]; then
    return 1
  fi

  if [[ "$common_git_dir" = /* ]]; then
    common_git_dir="$(canonical_path "$common_git_dir")"
  else
    common_git_dir="$(canonical_path "$dir/$common_git_dir")"
  fi

  canonical_path "$(dirname "$common_git_dir")"
}
```

- [ ] **Step 3: Add a command resolver for `git -C`**

Add this helper after `command_text()`:

```bash
git_command_cwd() {
  local command="$1"
  local base_dir="${2:-$cwd}"
  local -a words
  local i
  local selected_dir="$base_dir"

  read -r -a words <<<"$command"
  if [[ "${words[0]:-}" != "git" ]]; then
    return 1
  fi

  i=1
  while (( i < ${#words[@]} )); do
    case "${words[i]}" in
      -C)
        if [[ -z "${words[i + 1]:-}" ]]; then
          return 1
        fi
        if [[ "${words[i + 1]}" = /* ]]; then
          selected_dir="${words[i + 1]}"
        else
          selected_dir="$selected_dir/${words[i + 1]}"
        fi
        ((i += 2))
        ;;
      -c|--git-dir|--work-tree|--namespace)
        ((i += 2))
        ;;
      --git-dir=*|--work-tree=*|--namespace=*|-c*)
        ((i++))
        ;;
      --no-pager|--paginate|--no-optional-locks|--literal-pathspecs|--no-replace-objects)
        ((i++))
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -d "$selected_dir" ]]; then
    canonical_path "$selected_dir"
    return
  fi

  return 1
}
```

- [ ] **Step 4: Use the effective cwd in shell enforcement**

In the shell-tool block, compute `shell_cwd` and use it for repository checks:

```bash
repo_root="$(repo_root_for)"
if is_shell_tool; then
  command="$(command_text)"
  shell_cwd="$(effective_cwd)"
  command_cwd="$shell_cwd"
  if git_c_dir="$(git_command_cwd "$command" "$shell_cwd")"; then
    command_cwd="$git_c_dir"
  fi

  if referenced_root="$(command_referenced_main_worktree_root "$command")"; then
    if is_read_only_command "$command"; then
      exit 0
    fi

    deny "$(block_reason "$referenced_root")"
  fi

  repo_root="$(repo_root_for "$command_cwd")"
  if [[ -z "$repo_root" ]]; then
    if is_outside_repo_shell_command_allowed "$command"; then
      exit 0
    fi

    deny "$(block_reason "$(command_referenced_main_worktree_root "$command")")"
  fi

  if is_read_only_command "$command"; then
    exit 0
  fi
  repo_root="$(canonical_path "$repo_root")"

  if is_linked_worktree "$command_cwd"; then
    if has_shell_control_syntax "$command" && has_shell_path_indirection "$command"; then
      deny "$(block_reason "$(primary_worktree_root_for_current_repo "$command_cwd")")"
    fi

    exit 0
  fi

  deny "$(block_reason "$repo_root")"
fi
```

- [ ] **Step 5: Update relative command path scanning to use effective cwd**

Update `command_referenced_main_worktree_root()` to accept a base directory so relative paths are resolved against the command's effective directory instead of the hook session cwd:

```bash
command_referenced_main_worktree_root() {
  local command="$1"
  local base_dir="${2:-$cwd}"
  local -a words
  local word
  local candidate
  local root

  read -r -a words <<<"$command"

  for word in "${words[@]}"; do
    word="${word%\"}"
    word="${word#\"}"
    word="${word%\'}"
    word="${word#\'}"
    if [[ "$word" =~ ^[0-9]*(>>|>|<)(.*)$ ]]; then
      word="${BASH_REMATCH[2]}"
      word="${word%\"}"
      word="${word#\"}"
      word="${word%\'}"
      word="${word#\'}"
    fi
    word="${word%;}"
    word="${word#;}"
    word="${word%&}"
    word="${word#&}"
    word="${word%|}"
    word="${word#|}"
    word="${word%)}"
    word="${word#(}"
    case "$word" in
      '$HOME'/*)
        word="${HOME}${word#\$HOME}"
        ;;
      '${HOME}'/*)
        word="${HOME}${word#\$\{HOME\}}"
        ;;
      "~"/*)
        word="${HOME}${word#\~}"
        ;;
    esac
    case "$word" in
      /*)
        candidate="$word"
        ;;
      ./*|../*|*/*)
        candidate="$base_dir/$word"
        ;;
      *)
        continue
        ;;
    esac

    root="$(main_worktree_root_for_path "$candidate" || true)"
    if [[ -n "$root" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  done

  return 1
}
```

Then call it from the shell block as:

```bash
if referenced_root="$(command_referenced_main_worktree_root "$command" "$command_cwd")"; then
```

- [ ] **Step 6: Run the guard test**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: PASS and final line `ok worktree guard hook`.

- [ ] **Step 7: Commit the implementation**

Run:

```bash
git add codex/.codex/hooks/worktree-guard.sh codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "fix(codex): respect worktree guard effective cwd"
```

### Task 3: Verify Hook Installation Still Works

**Files:**
- Test: `codex/.codex/tests/test-codex-sync-hooks.sh`

- [ ] **Step 1: Run the sync hook test**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: PASS and final line `ok codex sync hook wiring`.

- [ ] **Step 2: Check for unexpected config changes**

Run:

```bash
git status --short
```

Expected: no changes other than the plan file before it is committed, or a clean tree after all commits. `codex/.codex/config.base.toml` should not be modified by this work.

- [ ] **Step 3: Commit the plan if it is still uncommitted**

Run:

```bash
git add docs/superpowers/plans/2026-05-20-codex-worktree-guard-effective-cwd.md
git commit -m "docs(codex): plan worktree guard cwd fix"
```

Expected: commit succeeds if the plan file is not already committed. If it is already committed before execution starts, skip this step.
