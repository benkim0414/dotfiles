# Codex Worktree Guard Registered Worktrees Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Codex worktree guard so write-capable operations are allowed inside any Git-registered linked worktree while primary checkout writes still require explicit approval.

**Architecture:** Parse `git worktree list --porcelain` into a normalized registry, classify candidate paths with longest-prefix matching, and use that classification before any common-git-dir or repo-root fallback. Keep the existing shell parser and destructive-command checks, but route direct writes, shell writes, and git-selected working directories through the same registry-aware classification.

**Tech Stack:** Bash, Git worktree metadata, `jq`, existing hook fixture tests in `codex/.codex/tests/test-worktree-guard-hook.sh`.

---

## File Structure

- Modify: `codex/.codex/hooks/worktree-guard.sh`
  - Restore the hook from its currently commented-out state.
  - Add worktree registry parsing and path classification helpers.
  - Replace primary/link detection calls that rely only on Git common-dir metadata with registry-aware classification.
  - Preserve existing read-only, destructive-command, and cross-boundary policies.
- Modify: `codex/.codex/tests/test-worktree-guard-hook.sh`
  - Add fixture paths for a nested registered worktree, a fake `.worktrees/plain-dir`, and an external registered worktree.
  - Add regression assertions for direct `apply_patch`, shell `apply_patch`, `git apply`, primary checkout blocking, fake worktree blocking, nested-prefix matching, and external registered worktree trust.
- Create: `docs/superpowers/plans/2026-05-21-codex-worktree-guard-registered-worktrees.md`
  - This implementation handoff.

## Task 1: Restore The Guard Script

**Files:**
- Modify: `codex/.codex/hooks/worktree-guard.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Write the failing baseline**

Run the existing hook test while the hook is still commented out:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: FAIL early because guarded primary-checkout writes are allowed or hook output is missing.

- [ ] **Step 2: Restore executable Bash content**

Remove exactly one leading `#` and one optional following space from each line in `codex/.codex/hooks/worktree-guard.sh`.

```bash
perl -0pi -e 's/^# ?//mg' codex/.codex/hooks/worktree-guard.sh
chmod +x codex/.codex/hooks/worktree-guard.sh
```

The first lines of the file should become:

```bash
#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || true)"
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)"
```

- [ ] **Step 3: Run the restored baseline**

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: FAIL on the existing registered-worktree bug or PASS if the current test suite does not yet cover it. Do not change behavior in this task beyond restoring the hook.

- [ ] **Step 4: Commit the restoration**

```bash
git add codex/.codex/hooks/worktree-guard.sh
git commit -m "fix(codex): restore worktree guard hook"
```

## Task 2: Add Registry-Based Worktree Classification

**Files:**
- Modify: `codex/.codex/hooks/worktree-guard.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Add failing classification tests**

In `setup_git_fixture`, add a project-local `.worktrees` registry case and a fake sibling:

```bash
NESTED_LINKED_WORKTREE=""
FAKE_WORKTREE_DIR=""
EXTERNAL_LINKED_WORKTREE=""
```

Inside `setup_git_fixture`, after the existing linked worktrees are created:

```bash
NESTED_LINKED_WORKTREE="$PRIMARY_REPO/.worktrees/nested-linked"
FAKE_WORKTREE_DIR="$PRIMARY_REPO/.worktrees/plain-dir"
EXTERNAL_LINKED_WORKTREE="$TEST_ROOT/external-linked"

mkdir -p "$PRIMARY_REPO/.worktrees" "$FAKE_WORKTREE_DIR"
git -C "$PRIMARY_REPO" worktree add "$NESTED_LINKED_WORKTREE" -b fixture-nested-worktree >/dev/null
git -C "$PRIMARY_REPO" worktree add "$EXTERNAL_LINKED_WORKTREE" -b fixture-external-worktree >/dev/null
```

Add these assertions near the existing linked-worktree assertions:

```bash
assert_allowed_json "$NESTED_LINKED_WORKTREE" "Write" "$(jq -cn --arg file_path "$NESTED_LINKED_WORKTREE/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_allowed_command "$OUTSIDE_DIR" "git -C \"$EXTERNAL_LINKED_WORKTREE\" add README.md"
assert_approval_required_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$FAKE_WORKTREE_DIR/generated.txt" '{file_path: $file_path, content: "blocked"}')" "unregistered worktree-like path"
```

- [ ] **Step 2: Run tests and confirm failure**

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: FAIL because nested registered worktrees are classified as primary and fake `.worktrees/plain-dir` does not yet have the distinct message.

- [ ] **Step 3: Add registry helper functions**

In `codex/.codex/hooks/worktree-guard.sh`, add these helpers after `path_is_inside`:

```bash
worktree_registry_for() {
  local dir="${1:-$cwd}"
  local line
  local path

  git -C "$dir" worktree list --porcelain 2>/dev/null |
    while IFS= read -r line; do
      case "$line" in
        worktree\ *)
          path="${line#worktree }"
          canonical_path "$path"
          ;;
      esac
    done
}

primary_worktree_from_registry() {
  local dir="${1:-$cwd}"

  worktree_registry_for "$dir" | sed -n '1p'
}

registered_linked_worktrees_for() {
  local dir="${1:-$cwd}"

  worktree_registry_for "$dir" | sed -n '2,$p'
}

registered_worktree_match_for_path() {
  local path="$1"
  local base_dir="${2:-$cwd}"
  local candidate
  local match=""
  local root

  candidate="$(canonical_path "$path")"
  while IFS= read -r root; do
    if path_is_inside "$candidate" "$root"; then
      if [[ -z "$match" || ${#root} -gt ${#match} ]]; then
        match="$root"
      fi
    fi
  done < <(worktree_registry_for "$base_dir")

  [[ -n "$match" ]] || return 1
  printf '%s\n' "$match"
}

path_is_under_primary_worktrees_dir() {
  local path="$1"
  local base_dir="${2:-$cwd}"
  local primary
  local candidate

  primary="$(primary_worktree_from_registry "$base_dir" || true)"
  [[ -n "$primary" ]] || return 1
  candidate="$(canonical_path "$path")"
  path_is_inside "$candidate" "$primary/.worktrees"
}

target_worktree_category() {
  local path="$1"
  local base_dir="${2:-$cwd}"
  local match
  local primary

  match="$(registered_worktree_match_for_path "$path" "$base_dir" || true)"
  primary="$(primary_worktree_from_registry "$base_dir" || true)"

  if [[ -n "$match" && -n "$primary" && "$match" == "$primary" ]]; then
    printf '%s\t%s\n' "primary-worktree" "$match"
    return 0
  fi

  if [[ -n "$match" ]]; then
    printf '%s\t%s\n' "registered-linked-worktree" "$match"
    return 0
  fi

  if path_is_under_primary_worktrees_dir "$path" "$base_dir"; then
    printf '%s\t%s\n' "unregistered-worktree-like-path" "$(canonical_path "$path")"
    return 0
  fi

  return 1
}
```

- [ ] **Step 4: Run tests for syntax**

```bash
bash -n codex/.codex/hooks/worktree-guard.sh
```

Expected: PASS with no output.

- [ ] **Step 5: Commit helper functions**

```bash
git add codex/.codex/hooks/worktree-guard.sh codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "test(codex): cover registered worktree classification"
```

## Task 3: Route Direct Writes Through Registry Classification

**Files:**
- Modify: `codex/.codex/hooks/worktree-guard.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Add direct apply_patch regression tests**

Add these assertions near the existing `apply_patch` tests:

```bash
assert_allowed_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn --arg file_path "$NESTED_LINKED_WORKTREE/direct-absolute.txt" '{cmd: "*** Begin Patch\n*** Add File: \($file_path)\n+allowed\n*** End Patch\n"}')"
assert_allowed_json "$NESTED_LINKED_WORKTREE" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: direct-relative.txt\n+allowed\n*** End Patch\n"}')"
assert_approval_required_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn --arg file_path "$FAKE_WORKTREE_DIR/direct-fake.txt" '{cmd: "*** Begin Patch\n*** Add File: \($file_path)\n+blocked\n*** End Patch\n"}')" "unregistered worktree-like path"
```

- [ ] **Step 2: Run tests and confirm failure**

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: FAIL on at least one new direct `apply_patch` assertion.

- [ ] **Step 3: Add approval helper for classified targets**

Add this helper after `approval_reason`:

```bash
approval_reason_for_classified_target() {
  local category="$1"
  local target="$2"

  case "$category" in
    primary-worktree)
      approval_reason "primary worktree" "$target"
      ;;
    unregistered-worktree-like-path)
      approval_reason "unregistered worktree-like path" "$target"
      ;;
    *)
      approval_reason "$category" "$target"
      ;;
  esac
}
```

- [ ] **Step 4: Replace direct write target loop**

In the `if is_direct_write_tool || is_mcp_write_tool; then` block, replace the per-target approval logic with:

```bash
  while IFS= read -r target; do
    found_target=1
    target_path="$(resolve_git_path "$target" "$cwd")"
    if classified="$(target_worktree_category "$target_path" "$cwd")"; then
      category="${classified%%$'\t'*}"
      target_root="${classified#*$'\t'}"
      case "$category" in
        registered-linked-worktree)
          continue
          ;;
        primary-worktree|unregistered-worktree-like-path)
          require_approval "$(approval_reason_for_classified_target "$category" "$target_root")"
          ;;
      esac
    elif target_repo_root="$(approval_required_worktree_root_for_path "$target_path" "$cwd")"; then
      require_approval "$(approval_reason "$(approval_category_for_target "$cwd" "$target_repo_root")" "$target_repo_root")"
    fi
  done < <(tool_target_paths)
```

- [ ] **Step 5: Verify direct write tests pass**

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: PASS or fail only on shell/git apply cases planned for Task 4.

- [ ] **Step 6: Commit direct write fix**

```bash
git add codex/.codex/hooks/worktree-guard.sh codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "fix(codex): trust registered worktree direct writes"
```

## Task 4: Route Shell apply_patch And git apply Through Registry Classification

**Files:**
- Modify: `codex/.codex/hooks/worktree-guard.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Add shell apply_patch and git apply regression tests**

Add these assertions near the linked-worktree command assertions:

```bash
assert_allowed_command_with_tool_workdir "$PRIMARY_REPO" "$NESTED_LINKED_WORKTREE" "apply_patch <<'PATCH'
*** Begin Patch
*** Add File: shell-apply-patch.txt
+allowed
*** End Patch
PATCH"

assert_allowed_command_with_tool_workdir "$PRIMARY_REPO" "$NESTED_LINKED_WORKTREE" "git apply <<'PATCH'
diff --git a/git-apply.txt b/git-apply.txt
new file mode 100644
index 0000000..30d8405
--- /dev/null
+++ b/git-apply.txt
@@ -0,0 +1 @@
+allowed
PATCH"

assert_approval_required_command "$NESTED_LINKED_WORKTREE" "git apply <<'PATCH'
diff --git a/../primary/git-apply-cross-boundary.txt b/../primary/git-apply-cross-boundary.txt
new file mode 100644
index 0000000..30d8405
--- /dev/null
+++ b/../primary/git-apply-cross-boundary.txt
@@ -0,0 +1 @@
+blocked
PATCH" "cross-boundary"
```

- [ ] **Step 2: Run tests and confirm failure**

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: FAIL on the shell `apply_patch` or `git apply` linked-worktree assertion.

- [ ] **Step 3: Add patch path extraction for shell commands**

Add these helpers near `apply_patch_target_paths`:

```bash
shell_patch_target_paths() {
  local command="$1"
  local line
  local path

  while IFS= read -r line; do
    case "$line" in
      "*** Add File: "*)
        path="${line#"*** Add File: "}"
        printf '%s\n' "$path"
        ;;
      "*** Update File: "*)
        path="${line#"*** Update File: "}"
        printf '%s\n' "$path"
        ;;
      "*** Delete File: "*)
        path="${line#"*** Delete File: "}"
        printf '%s\n' "$path"
        ;;
      "*** Move to: "*)
        path="${line#"*** Move to: "}"
        printf '%s\n' "$path"
        ;;
      "+++ b/"*)
        path="${line#"+++ b/"}"
        [[ "$path" != "/dev/null" ]] && printf '%s\n' "$path"
        ;;
      "--- a/"*)
        path="${line#"--- a/"}"
        [[ "$path" != "/dev/null" ]] && printf '%s\n' "$path"
        ;;
    esac
  done <<<"$command"
}

shell_command_targets_registered_worktree() {
  local command="$1"
  local base_dir="${2:-$cwd}"
  local target
  local target_path
  local classified
  local category

  if classified="$(target_worktree_category "$base_dir" "$base_dir")"; then
    category="${classified%%$'\t'*}"
    [[ "$category" == "registered-linked-worktree" ]] || return 1
  else
    return 1
  fi

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    target_path="$(resolve_git_path "$target" "$base_dir")"
    if classified="$(target_worktree_category "$target_path" "$base_dir")"; then
      category="${classified%%$'\t'*}"
      [[ "$category" == "registered-linked-worktree" ]] || return 1
    elif approval_required_worktree_root_for_path "$target_path" "$base_dir" >/dev/null; then
      return 1
    fi
  done < <(shell_patch_target_paths "$command")

  return 0
}
```

- [ ] **Step 4: Allow non-destructive shell writes in registered linked worktrees**

In the shell-tool block, before the final primary-worktree approval, make the existing linked-worktree allow check registry-aware:

```bash
  if classified="$(target_worktree_category "$command_cwd" "$shell_cwd")"; then
    category="${classified%%$'\t'*}"
    if [[ "$category" == "registered-linked-worktree" ]]; then
      if is_destructive_shell_command "$command"; then
        require_approval "$(approval_reason "destructive" "$command_cwd")"
      fi
      if shell_command_targets_registered_worktree "$command" "$command_cwd"; then
        exit 0
      fi
      if ! referenced_root="$(command_referenced_main_worktree_root "$command" "$command_cwd")"; then
        exit 0
      fi
    fi
  fi
```

- [ ] **Step 5: Verify shell and git apply tests pass**

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: PASS.

- [ ] **Step 6: Commit shell write fix**

```bash
git add codex/.codex/hooks/worktree-guard.sh codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "fix(codex): trust registered worktree shell writes"
```

## Task 5: Live Guard Verification

**Files:**
- Modify: none expected
- Test: live Codex PreToolUse guard

- [ ] **Step 1: Confirm automated tests pass**

```bash
bash -n codex/.codex/hooks/worktree-guard.sh
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: both PASS.

- [ ] **Step 2: Re-enable the hook if it is disabled in local config**

Confirm `codex/.codex/hooks/worktree-guard.sh` starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Expected: the hook is executable and not commented out.

- [ ] **Step 3: Run direct apply_patch live probe**

Use direct `apply_patch` to create:

```text
/home/benkim0414/workspace/dotfiles/.worktrees/tmux-blink-ipad-clipboard/.codex-guard-direct-apply-patch-test
```

Expected: allowed. Remove the file after confirming it exists.

- [ ] **Step 4: Run shell apply_patch live probe**

Run with workdir `/home/benkim0414/workspace/dotfiles/.worktrees/tmux-blink-ipad-clipboard`:

```bash
apply_patch <<'PATCH'
*** Begin Patch
*** Add File: .codex-guard-shell-apply-patch-test
+shell apply_patch guard probe
*** End Patch
PATCH
```

Expected: allowed. Remove the file after confirming it exists.

- [ ] **Step 5: Run git apply live probe**

Run with workdir `/home/benkim0414/workspace/dotfiles/.worktrees/tmux-blink-ipad-clipboard`:

```bash
git apply <<'PATCH'
diff --git a/.codex-guard-git-apply-test b/.codex-guard-git-apply-test
new file mode 100644
index 0000000..580c924
--- /dev/null
+++ b/.codex-guard-git-apply-test
@@ -0,0 +1 @@
+git apply guard probe
PATCH
```

Expected: allowed. Remove the file after confirming it exists.

- [ ] **Step 6: Confirm primary checkout still requires approval**

Use direct `apply_patch` to create:

```text
/home/benkim0414/workspace/dotfiles/.codex-guard-primary-direct-test
```

Expected: blocked with `Codex worktree guard detected primary worktree targeting /home/benkim0414/workspace/dotfiles; this requires explicit approval.`

- [ ] **Step 7: Confirm fake `.worktrees/` path is not trusted**

Use direct `apply_patch` to create:

```text
/home/benkim0414/workspace/dotfiles/.worktrees/plain-dir/.codex-guard-fake-worktree-test
```

Expected: blocked with `Codex worktree guard detected unregistered worktree-like path`.

- [ ] **Step 8: Commit live-verified implementation**

```bash
git status --short
git add codex/.codex/hooks/worktree-guard.sh codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "fix(codex): allow registered worktree guard writes"
```

Do not stage unrelated edits.

## Self-Review Notes

- Spec coverage: every approved requirement maps to a task: registry parsing in Task 2, direct writes in Task 3, shell and git apply in Task 4, primary/fake path/live verification in Task 5.
- Placeholder scan: no placeholder terms or undefined future work remains.
- Type and name consistency: plan uses `registered-linked-worktree`, `primary-worktree`, and `unregistered-worktree-like-path` consistently across helpers, messages, and tests.
