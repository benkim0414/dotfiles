# Codex Worktree Guard Direct-Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Narrow Codex worktree-guard enforcement to direct edit tools so shell and MCP exploration no longer trigger primary-checkout approval prompts.

**Architecture:** Keep the existing Codex hook wiring and path-aware direct edit checks, but stop routing shell and MCP executor tools through the worktree guard. Simplify `worktree-guard.sh` so stale configs still exit cleanly for shell/MCP tools while direct edit tools keep primary-worktree, linked-worktree, outside-repo, and cross-boundary behavior.

**Tech Stack:** Bash hooks, TOML Codex config, `jq`, Git worktrees, existing `codex-sync` shell test.

## Global Constraints

- Do not redesign the full Codex permission policy.
- Do not remove sandbox or approval-reviewer protections.
- Do not add a new session-state system like Claude Code's pending-worktree marker.
- Do not relax protections for direct edits to files in the primary checkout in this first pass.
- Use `apply_patch` for manual file edits.
- Work in `/home/benkim0414/workspace/dotfiles/.worktrees/worktree-guard-codex-direct-edits`.

---

## File Structure

- Modify `codex/.codex/config.base.toml`: narrow the worktree-guard `PreToolUse.matcher`.
- Modify `codex/.codex/hooks/worktree-guard.sh`: remove shell/MCP executor enforcement from runtime behavior and keep direct edit target handling.
- Modify `codex/.codex/tests/test-codex-sync-hooks.sh`: assert the generated matcher and direct edit behavior.
- No new runtime files are required.

### Task 1: Codex Config Matcher

**Files:**
- Modify: `codex/.codex/config.base.toml`
- Modify: `codex/.codex/tests/test-codex-sync-hooks.sh`

**Interfaces:**
- Consumes: existing `codex-sync` behavior that generates `codex/.codex/config.toml` from `config.base.toml`.
- Produces: generated Codex config where `worktree-guard.sh` is wired only to direct edit tool names.

- [ ] **Step 1: Update the generated config expectation first**

In `codex/.codex/tests/test-codex-sync-hooks.sh`, add an assertion immediately after the existing worktree-guard command assertion:

```bash
assert_file_contains "$CONFIG" 'matcher = "apply_patch|Edit|Write|MultiEdit|NotebookEdit"'
```

Keep the existing assertion:

```bash
assert_file_contains "$CONFIG" 'command = '\''bash "$HOME/.codex/hooks/worktree-guard.sh"'\'''
```

- [ ] **Step 2: Run the focused test and confirm it fails before implementation**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: FAIL before implementation because generated config still contains the broad worktree-guard matcher.

- [ ] **Step 3: Narrow the worktree-guard matcher in config**

In `codex/.codex/config.base.toml`, replace:

```toml
matcher = "apply_patch|Edit|Write|MultiEdit|NotebookEdit|local_shell|shell|shell_command|exec_command|Bash|Shell|mcp__"
```

with:

```toml
matcher = "apply_patch|Edit|Write|MultiEdit|NotebookEdit"
```

- [ ] **Step 4: Run the focused test again**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected:

```text
ok codex sync hook wiring
```

- [ ] **Step 5: Commit the config contract**

Run:

```bash
git status --short
git add codex/.codex/config.base.toml codex/.codex/tests/test-codex-sync-hooks.sh
git commit -m "fix(codex): narrow worktree guard matcher"
```

Expected: commit succeeds with only the config matcher and generated-config assertion changes.

### Task 2: Direct-Edit-Only Guard Runtime

**Files:**
- Modify: `codex/.codex/hooks/worktree-guard.sh`
- Test: `codex/.codex/tests/test-codex-sync-hooks.sh`

**Interfaces:**
- Consumes: Task 1 generated config where shell and MCP executor tools are no longer matched by the worktree guard.
- Produces: `worktree-guard.sh` behavior where only direct edit tools and MCP write-name tools can require approval; shell/MCP executor tools exit cleanly when stale configs still call the hook.

- [ ] **Step 1: Replace the MCP executor denial fixture with direct edit fixtures**

In `codex/.codex/tests/test-codex-sync-hooks.sh`, replace the block that starts with:

```bash
LIVE_PRIMARY_REPO="$TEST_ROOT/live-primary"
```

and ends with:

```bash
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("primary worktree")' >/dev/null <<<"$live_guard_output"
```

with this fixture block:

```bash
LIVE_PRIMARY_REPO="$TEST_ROOT/live-primary"
git init "$LIVE_PRIMARY_REPO" >/dev/null
git -C "$LIVE_PRIMARY_REPO" config user.email "codex@example.test"
git -C "$LIVE_PRIMARY_REPO" config user.name "Codex Test"
printf 'fixture\n' >"$LIVE_PRIMARY_REPO/README.md"
git -C "$LIVE_PRIMARY_REPO" add README.md
git -C "$LIVE_PRIMARY_REPO" commit -m "test: seed fixture" >/dev/null

primary_guard_output="$(
  jq -cn --arg cwd "$LIVE_PRIMARY_REPO" --arg tool_name "Write" '{
    hook_event_name:"PreToolUse",
    tool_name:$tool_name,
    cwd:$cwd,
    tool_input:{file_path:"generated.txt", content:"ok"}
  }' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/worktree-guard.sh"
)"
jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$primary_guard_output"
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("primary worktree")' >/dev/null <<<"$primary_guard_output"

git -C "$LIVE_PRIMARY_REPO" worktree add "$LIVE_PRIMARY_REPO/.worktrees/linked" -b linked-fixture >/dev/null
jq -cn --arg cwd "$LIVE_PRIMARY_REPO/.worktrees/linked" --arg tool_name "Write" '{
  hook_event_name:"PreToolUse",
  tool_name:$tool_name,
  cwd:$cwd,
  tool_input:{file_path:"linked-generated.txt", content:"ok"}
}' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/worktree-guard.sh" >/dev/null

OUTSIDE_REPO="$TEST_ROOT/outside-repo"
mkdir -p "$OUTSIDE_REPO"
jq -cn --arg cwd "$OUTSIDE_REPO" --arg tool_name "Write" '{
  hook_event_name:"PreToolUse",
  tool_name:$tool_name,
  cwd:$cwd,
  tool_input:{file_path:"outside-generated.txt", content:"ok"}
}' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/worktree-guard.sh" >/dev/null

cross_boundary_output="$(
  jq -cn --arg cwd "$LIVE_PRIMARY_REPO/.worktrees/linked" --arg target "$LIVE_PRIMARY_REPO/README.md" --arg tool_name "Write" '{
    hook_event_name:"PreToolUse",
    tool_name:$tool_name,
    cwd:$cwd,
    tool_input:{file_path:$target, content:"changed"}
  }' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/worktree-guard.sh"
)"
jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$cross_boundary_output"
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("cross-boundary")' >/dev/null <<<"$cross_boundary_output"

mcp_guard_output="$(
  jq -cn --arg cwd "$LIVE_PRIMARY_REPO" --arg tool_name "mcp__context_mode__.ctx_execute" '{
    hook_event_name:"PreToolUse",
    tool_name:$tool_name,
    cwd:$cwd,
    tool_input:{language:"shell", code:"touch generated.txt"}
  }' | env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin" bash "$CODEX_HOME/hooks/worktree-guard.sh"
)"
[[ -z "$mcp_guard_output" ]]
```

- [ ] **Step 2: Run the focused test and confirm it fails before implementation**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected: FAIL before implementation because `worktree-guard.sh` still denies the stale MCP executor fixture.

- [ ] **Step 3: Replace shell and MCP executor dispatch with a no-op**

In `codex/.codex/hooks/worktree-guard.sh`, delete the runtime block that starts with:

```bash
repo_root="$(repo_root_for)"
if is_shell_tool; then
```

and ends immediately before:

```bash
if is_direct_write_tool || is_mcp_write_tool; then
```

Replace that deleted block with:

```bash
if is_shell_tool || is_mcp_executor_tool; then
  exit 0
fi

repo_root="$(repo_root_for)"

if is_direct_write_tool || is_mcp_write_tool; then
```

This preserves stale-config compatibility: even if an old generated config still routes shell/MCP executor tools to the guard, the hook does not block them.

- [ ] **Step 4: Leave helper cleanup out of scope**

Do not delete helper functions that become unused after the dispatch removal. Keeping them for this change keeps the patch focused on behavior and test coverage.

- [ ] **Step 5: Verify direct edit target extraction still covers apply_patch**

Run:

```bash
jq -n --arg tool_name "functions.apply_patch" --arg cwd "$PWD" '{
  hook_event_name:"PreToolUse",
  tool_name:$tool_name,
  cwd:$cwd,
  tool_input:"*** Begin Patch\n*** Add File: generated.txt\n+ok\n*** End Patch\n"
}' | bash codex/.codex/hooks/worktree-guard.sh
```

Expected in the feature linked worktree: no output and exit code `0`, because direct edits in the active linked worktree are allowed.

- [ ] **Step 6: Run the focused sync and guard test**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected:

```text
ok codex sync hook wiring
```

- [ ] **Step 7: Run shell syntax and whitespace checks**

Run:

```bash
bash -n codex/.codex/hooks/worktree-guard.sh
git diff --check
```

Expected: both commands exit `0` with no output.

- [ ] **Step 8: Commit the runtime change and fixtures**

Run:

```bash
git status --short
git add codex/.codex/hooks/worktree-guard.sh codex/.codex/tests/test-codex-sync-hooks.sh
git commit -m "fix(codex): narrow worktree guard to direct edits"
```

Expected: commit succeeds with only the hook runtime and direct edit fixture changes staged.

### Task 3: Final Verification And Review Prep

**Files:**
- Verify: `codex/.codex/config.base.toml`
- Verify: `codex/.codex/hooks/worktree-guard.sh`
- Verify: `codex/.codex/tests/test-codex-sync-hooks.sh`

**Interfaces:**
- Consumes: Task 1 and Task 2 commits.
- Produces: a clean branch ready for code review with concrete verification output.

- [ ] **Step 1: Run full focused verification**

Run:

```bash
bash codex/.codex/tests/test-codex-sync-hooks.sh
bash -n codex/.codex/hooks/worktree-guard.sh
git diff --check
```

Expected:

```text
ok codex sync hook wiring
```

`bash -n` and `git diff --check` should produce no output and exit `0`.

- [ ] **Step 2: Inspect final diff**

Run:

```bash
git status --short
git log --oneline -5
git diff HEAD~2..HEAD -- codex/.codex/config.base.toml codex/.codex/hooks/worktree-guard.sh codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected:

- `git status --short` is clean.
- Recent commits include `fix(codex): narrow worktree guard matcher` and `fix(codex): narrow worktree guard to direct edits`.
- Diff shows the narrower matcher, direct edit fixtures, and direct-edit-only guard runtime.

- [ ] **Step 3: Request code review**

Invoke `superpowers:requesting-code-review`.

Expected: reviewer checks behavior against the approved spec and this plan, with special attention to stale-config shell/MCP no-op behavior and primary-worktree direct edit denial.
