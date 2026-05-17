# Context Mode Approval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow all `context-mode` MCP tools to run without approval prompts while preserving normal approval behavior for unrelated commands.

**Architecture:** Keep durable Codex configuration in `codex/.codex/config.base.toml` and regenerate `codex/.codex/config.toml` with the existing `codex-sync` helper. Use Codex's per-MCP-server `default_tools_approval_mode = "approve"` setting instead of weakening global `approval_policy`.

**Tech Stack:** Codex CLI TOML config, Bash, `rg`, existing `bin/.local/bin/codex-sync`, context-mode MCP tool diagnostics.

---

## File Structure

- Modify: `codex/.codex/config.base.toml`
  - Responsibility: durable checked-in Codex configuration. Add only the `default_tools_approval_mode = "approve"` setting to the existing `[mcp_servers.context-mode]` block.
- Modify: `codex/.codex/config.toml`
  - Responsibility: generated local Codex configuration copied from `config.base.toml` by `bin/.local/bin/codex-sync`. This file is gitignored but should be refreshed so the current checkout takes effect immediately.
- Read-only: `bin/.local/bin/codex-sync`
  - Responsibility: copy `config.base.toml` to `config.toml`.
- Read-only: `docs/superpowers/specs/2026-05-17-context-mode-approval-design.md`
  - Responsibility: approved design source for this plan.

## Task 1: Add Context Mode MCP Tool Auto-Approval

**Files:**
- Modify: `codex/.codex/config.base.toml`
- Modify: `codex/.codex/config.toml`
- Read-only: `bin/.local/bin/codex-sync`

- [ ] **Step 1: Verify the setting is absent before the edit**

Run:

```bash
rg -n 'default_tools_approval_mode = "approve"' codex/.codex/config.base.toml codex/.codex/config.toml
```

Expected before implementation: exit code `1` and no output. If the command already matches, inspect both files and skip to Step 4.

- [ ] **Step 2: Add the MCP server approval mode to the base config**

Use `apply_patch` to replace this block in `codex/.codex/config.base.toml`:

```toml
[mcp_servers.context-mode]
# Launch context-mode as a Codex MCP server.
command = "context-mode"
```

with:

```toml
[mcp_servers.context-mode]
# Launch context-mode as a Codex MCP server.
command = "context-mode"
# Allow all context-mode MCP tools without per-call approval prompts.
default_tools_approval_mode = "approve"
```

- [ ] **Step 3: Verify the base config has exactly the intended setting**

Run:

```bash
rg -n '^\[mcp_servers\.context-mode\]|^command = "context-mode"$|^default_tools_approval_mode = "approve"$|^approval_policy = "on-request"$' codex/.codex/config.base.toml
```

Expected: output includes these four lines in `codex/.codex/config.base.toml`:

```text
approval_policy = "on-request"
[mcp_servers.context-mode]
command = "context-mode"
default_tools_approval_mode = "approve"
```

- [ ] **Step 4: Regenerate the live Codex config**

Run:

```bash
bin/.local/bin/codex-sync
```

Expected: exit code `0` and no output.

- [ ] **Step 5: Verify the generated config matches the base approval settings**

Run:

```bash
rg -n '^\[mcp_servers\.context-mode\]|^command = "context-mode"$|^default_tools_approval_mode = "approve"$|^approval_policy = "on-request"$' codex/.codex/config.toml
```

Expected: output includes these four lines in `codex/.codex/config.toml`:

```text
approval_policy = "on-request"
[mcp_servers.context-mode]
command = "context-mode"
default_tools_approval_mode = "approve"
```

- [ ] **Step 6: Confirm no global approval weakening was introduced**

Run:

```bash
rg -n 'approval_policy = "never"|dangerously-bypass|danger-full-access' codex/.codex/config.base.toml codex/.codex/config.toml
```

Expected: exit code `1` and no output.

- [ ] **Step 7: Verify context-mode MCP diagnostics**

Run the MCP tool:

```text
mcp__context_mode__ctx_doctor
```

Expected: the tool returns a context-mode status report. The report may contain warnings about optional setup, but the MCP tool call itself should complete without needing an approval prompt.

- [ ] **Step 8: Review the diff**

Run:

```bash
git diff -- codex/.codex/config.base.toml codex/.codex/config.toml
```

Expected: the only config behavior change is the added `default_tools_approval_mode = "approve"` line under `[mcp_servers.context-mode]`. `codex/.codex/config.toml` should mirror `config.base.toml`.

- [ ] **Step 9: Commit the config change**

Run:

```bash
git add codex/.codex/config.base.toml codex/.codex/config.toml
git commit -m "feat(codex): auto-approve context-mode mcp tools"
```

Expected: commit succeeds. If `codex/.codex/config.toml` is ignored and cannot be staged without force, commit only `codex/.codex/config.base.toml` and leave the regenerated local config unstaged:

```bash
git add codex/.codex/config.base.toml
git commit -m "feat(codex): auto-approve context-mode mcp tools"
```

## Task 2: Final Verification

**Files:**
- Read-only: `codex/.codex/config.base.toml`
- Read-only: `codex/.codex/config.toml`

- [ ] **Step 1: Confirm durable and live config both contain the scoped approval**

Run:

```bash
rg -n 'default_tools_approval_mode = "approve"' codex/.codex/config.base.toml codex/.codex/config.toml
```

Expected: one match in `config.base.toml` and one match in `config.toml`.

- [ ] **Step 2: Confirm global approval policy is unchanged**

Run:

```bash
rg -n '^approval_policy = "on-request"$' codex/.codex/config.base.toml codex/.codex/config.toml
```

Expected: one match in `config.base.toml` and one match in `config.toml`.

- [ ] **Step 3: Confirm working tree only has unrelated pre-existing files or the intended commit**

Run:

```bash
git status --short
```

Expected after committing: no tracked config changes remain. Pre-existing unrelated untracked files such as other draft plan documents may still appear and should not be modified for this task.
