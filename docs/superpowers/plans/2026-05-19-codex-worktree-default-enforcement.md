# Codex Worktree Default Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global Codex hook that blocks repository writes from any Git repository's main worktree and directs Codex to continue from a linked `.worktrees/<slug>` checkout.

**Architecture:** Add a dedicated `worktree-guard.sh` PreToolUse hook instead of expanding the atomic commit hook. The guard parses the Codex hook payload, resolves the runtime Git repository from `cwd`, allows linked worktrees and non-repo directories, and denies write-capable tool calls that target repo files from a main worktree. Config and sync changes install the hook globally from the dotfiles source.

**Tech Stack:** Bash, `jq`, Git worktrees, Codex `config.toml` hooks, GNU Stow-style dotfiles sync, shell tests.

---

## Source Material

- Design spec: `docs/superpowers/specs/2026-05-19-codex-worktree-default-enforcement-design.md`
- Existing hook: `codex/.codex/hooks/atomic-commits.sh`
- Existing hook tests: `codex/.codex/tests/test-atomic-commits-hook.sh`
- Existing sync test: `codex/.codex/tests/test-codex-sync-hooks.sh`
- Existing config: `codex/.codex/config.base.toml`
- Existing sync script: `bin/.local/bin/codex-sync`

## File Structure

- Create `codex/.codex/hooks/worktree-guard.sh`
  - Owns worktree enforcement only.
  - Reads Codex hook JSON from stdin.
  - Emits Codex `permissionDecision: "deny"` JSON on blocked writes.
- Create `codex/.codex/tests/test-worktree-guard-hook.sh`
  - Uses temp repositories and linked worktrees.
  - Exercises direct file tools and shell command tools.
- Modify `codex/.codex/config.base.toml`
  - Adds a new `[[hooks.PreToolUse]]` entry for `worktree-guard.sh`.
  - Leaves the existing `atomic-commits.sh` hook unchanged.
- Modify `bin/.local/bin/codex-sync`
  - Requires and wires `worktree-guard.sh` alongside `atomic-commits.sh`.
- Modify `codex/.codex/tests/test-codex-sync-hooks.sh`
  - Copies the new hook into the fixture.
  - Asserts the generated config and live symlink include the new hook.
  - Smoke-runs the new hook from a non-repo directory.
- Modify `codex/.codex/AGENTS.md`
  - Documents that Codex changes and generated artifacts belong in linked worktrees.

---

### Task 1: Add Failing Worktree Guard Hook Tests

**Files:**
- Create: `codex/.codex/tests/test-worktree-guard-hook.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Create the failing test file**

Create `codex/.codex/tests/test-worktree-guard-hook.sh` with this exact content:

```bash
#!/usr/bin/env bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
HOOK="$HOOK_ROOT/worktree-guard.sh"
TEST_ROOT=""
PRIMARY_REPO=""
LINKED_WORKTREE=""
OUTSIDE_DIR=""

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
  OUTSIDE_DIR="$TEST_ROOT/outside"

  mkdir -p "$OUTSIDE_DIR"
  git init "$PRIMARY_REPO" >/dev/null
  git -C "$PRIMARY_REPO" config user.email "codex@example.test"
  git -C "$PRIMARY_REPO" config user.name "Codex Test"
  printf 'fixture\n' >"$PRIMARY_REPO/README.md"
  git -C "$PRIMARY_REPO" add README.md
  git -C "$PRIMARY_REPO" commit -m "test: seed fixture" >/dev/null
  git -C "$PRIMARY_REPO" worktree add "$LINKED_WORKTREE" -b fixture-worktree >/dev/null
}

run_hook_json() {
  local cwd="$1"
  local tool_name="$2"
  local tool_input="$3"

  jq -cn --arg cwd "$cwd" --arg tool_name "$tool_name" --argjson tool_input "$tool_input" '{
    hook_event_name: "PreToolUse",
    tool_name: $tool_name,
    cwd: $cwd,
    tool_input: $tool_input
  }' | bash "$HOOK"
}

assert_denied_json() {
  local cwd="$1"
  local tool_name="$2"
  local tool_input="$3"
  local output

  output="$(run_hook_json "$cwd" "$tool_name" "$tool_input")"
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"
  jq -e '.hookSpecificOutput.permissionDecisionReason | contains("main worktree")' >/dev/null <<<"$output"
  jq -e '.hookSpecificOutput.permissionDecisionReason | contains("git worktree add .worktrees/")' >/dev/null <<<"$output"
  echo "ok denied $tool_name in $cwd"
}

assert_allowed_json() {
  local cwd="$1"
  local tool_name="$2"
  local tool_input="$3"
  local output

  output="$(run_hook_json "$cwd" "$tool_name" "$tool_input")"
  if [[ -n "$output" ]] && jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    echo "expected allowed but denied: $tool_name in $cwd" >&2
    echo "$output" >&2
    return 1
  fi
  echo "ok allowed $tool_name in $cwd"
}

assert_denied_command() {
  local cwd="$1"
  local command="$2"
  assert_denied_json "$cwd" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')"
}

assert_allowed_command() {
  local cwd="$1"
  local command="$2"
  assert_allowed_json "$cwd" "Bash" "$(jq -cn --arg command "$command" '{command: $command}')"
}

if [[ ! -x "$HOOK" ]]; then
  echo "missing executable hook: $HOOK" >&2
  exit 1
fi

setup_git_fixture

assert_allowed_json "$OUTSIDE_DIR" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: note.txt\n+ok\n*** End Patch\n"}')"
assert_denied_json "$PRIMARY_REPO" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: repo.txt\n+blocked\n*** End Patch\n"}')"
assert_denied_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$PRIMARY_REPO/generated.txt" '{file_path: $file_path, content: "blocked"}')"
assert_allowed_json "$PRIMARY_REPO" "Write" "$(jq -cn --arg file_path "$OUTSIDE_DIR/generated.txt" '{file_path: $file_path, content: "allowed"}')"
assert_allowed_json "$LINKED_WORKTREE" "apply_patch" "$(jq -cn '{cmd: "*** Begin Patch\n*** Add File: repo.txt\n+allowed\n*** End Patch\n"}')"
assert_allowed_json "$LINKED_WORKTREE" "Write" "$(jq -cn --arg file_path "$LINKED_WORKTREE/generated.txt" '{file_path: $file_path, content: "allowed"}')"

assert_allowed_command "$PRIMARY_REPO" "git status --short"
assert_allowed_command "$PRIMARY_REPO" "git diff -- README.md"
assert_allowed_command "$PRIMARY_REPO" "rg -n fixture README.md"
assert_allowed_command "$PRIMARY_REPO" "sed -n '1,20p' README.md"
assert_allowed_command "$PRIMARY_REPO" "ls"
assert_allowed_command "$PRIMARY_REPO" "pwd"
assert_denied_command "$PRIMARY_REPO" "printf 'blocked\n' > generated.txt"
assert_denied_command "$PRIMARY_REPO" "touch generated.txt"
assert_denied_command "$PRIMARY_REPO" "git add README.md"
assert_denied_command "$PRIMARY_REPO" "apply_patch <<'PATCH'
*** Begin Patch
*** Add File: generated.txt
+blocked
*** End Patch
PATCH"
assert_allowed_command "$LINKED_WORKTREE" "printf 'allowed\n' > generated.txt"

printf 'ok worktree guard hook\n'
```

- [ ] **Step 2: Run the new test and verify it fails because the hook does not exist**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: FAIL with `missing executable hook: .../worktree-guard.sh`.

- [ ] **Step 3: Commit the failing tests**

Run:

```bash
git add codex/.codex/tests/test-worktree-guard-hook.sh
git commit -m "test(codex): cover worktree guard behavior"
```

Expected: commit succeeds.

---

### Task 2: Implement the Worktree Guard Hook

**Files:**
- Create: `codex/.codex/hooks/worktree-guard.sh`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Create the hook implementation**

Create `codex/.codex/hooks/worktree-guard.sh` with this exact content:

```bash
#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || true)"
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)"

if [[ -z "$cwd" || ! -d "$cwd" ]]; then
  cwd="$PWD"
fi

deny() {
  local reason="$1"

  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

canonical_path() {
  local path="$1"
  local dir
  local base

  if [[ -d "$path" ]]; then
    (cd "$path" && pwd -P)
    return
  fi

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if [[ -d "$dir" ]]; then
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
  else
    printf '%s\n' "$path"
  fi
}

repo_root_for() {
  git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true
}

resolve_git_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    canonical_path "$path"
  else
    canonical_path "$cwd/$path"
  fi
}

is_linked_worktree() {
  local absolute_git_dir
  local common_git_dir

  absolute_git_dir="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null || true)"
  common_git_dir="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)"

  if [[ -z "$absolute_git_dir" || -z "$common_git_dir" ]]; then
    return 1
  fi

  absolute_git_dir="$(canonical_path "$absolute_git_dir")"
  common_git_dir="$(resolve_git_path "$common_git_dir")"

  [[ "$absolute_git_dir" != "$common_git_dir" ]]
}

path_is_inside() {
  local path="$1"
  local root="$2"

  case "$path" in
    "$root"|"$root"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tool_target_path() {
  jq -r '
    .tool_input.file_path //
    .tool_input.path //
    .tool_input.target_file //
    .tool_input.filename //
    empty
  ' <<<"$input" 2>/dev/null || true
}

command_text() {
  jq -r '.tool_input.command // .tool_input.cmd // ""' <<<"$input" 2>/dev/null || true
}

is_read_only_command() {
  local command="$1"

  case "$command" in
    ""|\
    "pwd"|\
    "ls"|\
    "ls "*|\
    "rg "*|\
    "grep "*|\
    "find "*|\
    "sed -n "*|\
    "cat "*|\
    "git status"*|\
    "git diff"*|\
    "git log"*|\
    "git show"*|\
    "git branch"*|\
    "git worktree list"*|\
    "git rev-parse"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_shell_tool() {
  case "$tool_name" in
    Bash|Shell|shell|shell_command|local_shell|exec_command|functions.exec_command)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_direct_write_tool() {
  case "$tool_name" in
    apply_patch|Edit|Write|MultiEdit|NotebookEdit|functions.apply_patch)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_mcp_write_tool() {
  case "$tool_name" in
    *write*|*edit*|*create*|*delete*|*apply_patch*|*move*|*rename*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

block_reason() {
  local root="$1"

  cat <<MSG
Codex worktree guard blocked this write because the current directory is the repository's main worktree.

Create a linked worktree and continue there:
  git worktree add .worktrees/<slug> -b <branch>
  cd .worktrees/<slug>

All repo changes and generated artifacts, including docs/superpowers/specs/, docs/superpowers/plans/, docs/solutions/, code, and config files, belong in the feature worktree.

Repository root: $root
MSG
}

repo_root="$(repo_root_for)"
if [[ -z "$repo_root" ]]; then
  exit 0
fi
repo_root="$(canonical_path "$repo_root")"

if is_linked_worktree; then
  exit 0
fi

if is_shell_tool; then
  command="$(command_text)"
  if is_read_only_command "$command"; then
    exit 0
  fi
  deny "$(block_reason "$repo_root")"
fi

if is_direct_write_tool || is_mcp_write_tool; then
  target="$(tool_target_path)"
  if [[ -n "$target" ]]; then
    case "$target" in
      /*)
        target_path="$(canonical_path "$target")"
        ;;
      *)
        target_path="$(canonical_path "$cwd/$target")"
        ;;
    esac

    if ! path_is_inside "$target_path" "$repo_root"; then
      exit 0
    fi
  fi

  deny "$(block_reason "$repo_root")"
fi

exit 0
```

- [ ] **Step 2: Make the hook executable**

Run:

```bash
chmod +x codex/.codex/hooks/worktree-guard.sh
```

Expected: command succeeds.

- [ ] **Step 3: Run the hook tests**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: PASS and prints `ok worktree guard hook`.

- [ ] **Step 4: Run the existing atomic hook tests to verify no behavior changed**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: PASS and prints `ok atomic commits hook`.

- [ ] **Step 5: Commit the hook implementation**

Run:

```bash
git add codex/.codex/hooks/worktree-guard.sh
git commit -m "feat(codex): block main-worktree writes"
```

Expected: commit succeeds.

---

### Task 3: Wire the Hook Into Codex Config and Sync

**Files:**
- Modify: `codex/.codex/config.base.toml`
- Modify: `bin/.local/bin/codex-sync`
- Modify: `codex/.codex/tests/test-codex-sync-hooks.sh`
- Test: `codex/.codex/tests/test-codex-sync-hooks.sh`

- [ ] **Step 1: Add the PreToolUse hook to config**

In `codex/.codex/config.base.toml`, add this block immediately after the existing `atomic-commits.sh` `[[hooks.PreToolUse]]` block and before the context-mode `[[hooks.PreToolUse]]` block:

```toml
[[hooks.PreToolUse]]
matcher = "apply_patch|Edit|Write|MultiEdit|NotebookEdit|local_shell|shell|shell_command|exec_command|Bash|Shell|mcp__"

[[hooks.PreToolUse.hooks]]
type = "command"
command = 'bash "$HOME/.codex/hooks/worktree-guard.sh"'
timeout = 10
statusMessage = "Checking worktree isolation"
```

Expected: the atomic commit hook remains unchanged and still appears before this new block.

- [ ] **Step 2: Update `codex-sync` to require and wire the new hook**

In `bin/.local/bin/codex-sync`, make these exact changes.

Near the existing tracked hook variables, change:

```bash
tracked_atomic_hook="$codex_dir/hooks/atomic-commits.sh"
```

to:

```bash
tracked_atomic_hook="$codex_dir/hooks/atomic-commits.sh"
tracked_worktree_hook="$codex_dir/hooks/worktree-guard.sh"
```

Near the live hook variables, change:

```bash
live_atomic_hook="$live_hooks_dir/atomic-commits.sh"
```

to:

```bash
live_atomic_hook="$live_hooks_dir/atomic-commits.sh"
live_worktree_hook="$live_hooks_dir/worktree-guard.sh"
```

Near the required files, change:

```bash
require_file "$base_config"
require_file "$tracked_atomic_hook"
```

to:

```bash
require_file "$base_config"
require_file "$tracked_atomic_hook"
require_file "$tracked_worktree_hook"
```

Near the symlink wiring, change:

```bash
replace_symlink "$live_config" "$generated_config"
replace_symlink "$live_atomic_hook" "$tracked_atomic_hook"
remove_managed_legacy_hooks_json
```

to:

```bash
replace_symlink "$live_config" "$generated_config"
replace_symlink "$live_atomic_hook" "$tracked_atomic_hook"
replace_symlink "$live_worktree_hook" "$tracked_worktree_hook"
remove_managed_legacy_hooks_json
```

- [ ] **Step 3: Update the sync fixture to copy the new hook**

In `codex/.codex/tests/test-codex-sync-hooks.sh`, inside `copy_sync_fixture()`, change:

```bash
cp "$REPO_ROOT/codex/.codex/hooks/atomic-commits.sh" "$dotfiles/codex/.codex/hooks/atomic-commits.sh"
```

to:

```bash
cp "$REPO_ROOT/codex/.codex/hooks/atomic-commits.sh" "$dotfiles/codex/.codex/hooks/atomic-commits.sh"
cp "$REPO_ROOT/codex/.codex/hooks/worktree-guard.sh" "$dotfiles/codex/.codex/hooks/worktree-guard.sh"
```

- [ ] **Step 4: Assert config and live symlink wiring**

In `codex/.codex/tests/test-codex-sync-hooks.sh`, after the existing assertion for the atomic hook command:

```bash
assert_file_contains "$CONFIG" 'command = '\''bash "$HOME/.codex/hooks/atomic-commits.sh"'\'''
```

add:

```bash
assert_file_contains "$CONFIG" 'command = '\''bash "$HOME/.codex/hooks/worktree-guard.sh"'\'''
```

After the existing atomic hook symlink assertion:

```bash
[[ "$(readlink "$CODEX_HOME/hooks/atomic-commits.sh")" == "$DOTFILES/codex/.codex/hooks/atomic-commits.sh" ]]
```

add:

```bash
[[ "$(readlink "$CODEX_HOME/hooks/worktree-guard.sh")" == "$DOTFILES/codex/.codex/hooks/worktree-guard.sh" ]]
```

After the atomic hook smoke run:

```bash
printf '{"tool_input":{"command":"echo ok"}}' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/atomic-commits.sh"
```

add:

```bash
jq -cn --arg cwd "$TEST_ROOT" '{
  hook_event_name: "PreToolUse",
  tool_name: "Write",
  cwd: $cwd,
  tool_input: {
    file_path: "outside.txt",
    content: "ok"
  }
}' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/worktree-guard.sh"
```

After the unmanaged atomic hook symlink assertion:

```bash
[[ "$(readlink "$UNMANAGED_CODEX_HOME/hooks/atomic-commits.sh")" == "/before/atomic-commits.sh" ]]
```

add:

```bash
assert_path_absent "$UNMANAGED_CODEX_HOME/hooks/worktree-guard.sh"
```

After each existing non-primary or inferred assertion that `atomic-commits.sh` is absent, add the matching worktree hook assertion:

```bash
assert_path_absent "$NONPRIMARY_HOME/.codex/hooks/worktree-guard.sh"
assert_path_absent "$INFERRED_HOME/.codex/hooks/worktree-guard.sh"
```

- [ ] **Step 5: Run sync tests**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: PASS and prints `ok codex sync hook wiring`.

- [ ] **Step 6: Run all hook tests**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
bash codex/.codex/tests/test-atomic-commits-hook.sh
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: all three pass.

- [ ] **Step 7: Commit config and sync wiring**

Run:

```bash
git add codex/.codex/config.base.toml bin/.local/bin/codex-sync codex/.codex/tests/test-codex-sync-hooks.sh
git commit -m "feat(codex): wire worktree guard hook"
```

Expected: commit succeeds.

---

### Task 4: Document the Codex Worktree Workflow

**Files:**
- Modify: `codex/.codex/AGENTS.md`
- Test: `codex/.codex/tests/test-worktree-guard-hook.sh`

- [ ] **Step 1: Add workflow guidance to Codex instructions**

In `codex/.codex/AGENTS.md`, add this section after the `## Subagent Approval Contract` section and before `## Git Commit Workflow`:

```markdown
## Worktree Isolation

- For any change in a Git repository, work from a linked Git worktree rather than the repository's main worktree.
- Use the repository-local convention `git worktree add .worktrees/<slug> -b <branch>` and continue from `.worktrees/<slug>`.
- Generated workflow artifacts are part of the feature branch. This includes Superpowers specs in `docs/superpowers/specs/`, Superpowers plans in `docs/superpowers/plans/`, Compound solution docs in `docs/solutions/`, and normal code or config changes.
- A Codex PreToolUse hook enforces this for repo writes. If it blocks a write, create or enter the linked worktree named in the hook message and continue there.
```

- [ ] **Step 2: Run hook tests after documentation change**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
```

Expected: PASS and prints `ok worktree guard hook`.

- [ ] **Step 3: Commit documentation**

Run:

```bash
git add codex/.codex/AGENTS.md
git commit -m "docs(codex): explain worktree isolation"
```

Expected: commit succeeds.

---

### Task 5: Final Verification

**Files:**
- Verify: all files changed by Tasks 1-4

- [ ] **Step 1: Run all Codex hook tests**

Run:

```bash
bash codex/.codex/tests/test-worktree-guard-hook.sh
bash codex/.codex/tests/test-atomic-commits-hook.sh
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected:

```text
ok worktree guard hook
ok atomic commits hook
ok codex sync hook wiring
```

- [ ] **Step 2: Inspect the final diff**

Run:

```bash
git status --short
git diff --stat HEAD~4..HEAD
git log --oneline --decorate -5
```

Expected:

- `git status --short` is empty.
- The diff includes only:
  - `bin/.local/bin/codex-sync`
  - `codex/.codex/AGENTS.md`
  - `codex/.codex/config.base.toml`
  - `codex/.codex/hooks/worktree-guard.sh`
  - `codex/.codex/tests/test-codex-sync-hooks.sh`
  - `codex/.codex/tests/test-worktree-guard-hook.sh`
  - this plan and its design spec from earlier commits

- [ ] **Step 3: Run final code review**

Use `superpowers:requesting-code-review` for the full implementation range.

Run:

```bash
git rev-parse 383467b
git rev-parse HEAD
```

Use `383467b` as the base SHA if the branch still starts from `main` at `383467b`. Use the current `HEAD` as the head SHA.

Expected: reviewer finds no Critical or Important issues. Fix any valid findings before finishing.
