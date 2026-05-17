# Context Mode Codex Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install `context-mode` and configure Codex CLI to use it through MCP plus upstream-style `hooks.json` hook registration.

**Architecture:** Keep durable Codex settings in `codex/.codex/config.base.toml`, because this repo generates the live `config.toml` from that base file. Put context-mode's hook integration in a tracked `codex/.codex/hooks.json`, matching the upstream Codex install instructions. Leave `codex/.codex/AGENTS.md` and the existing atomic-commit TOML hook unchanged.

**Tech Stack:** Codex CLI config TOML, Codex hooks JSON, npm global package install, Bash, `jq`, `rg`, existing `codex-sync` helper.

---

## File Structure

- Modify: `codex/.codex/config.base.toml`
  - Responsibility: durable Codex base settings. Add only the `context-mode` MCP server entry.
- Create: `codex/.codex/hooks.json`
  - Responsibility: durable upstream-style Codex hook registrations for context-mode session and tool tracking.
- Generated local-only: `codex/.codex/config.toml`
  - Responsibility: generated Codex config copied from `config.base.toml` by `bin/.local/bin/codex-sync`. It is gitignored and must not be committed.
- Read-only verification: `codex/.codex/AGENTS.md`
  - Responsibility: existing global Codex instructions. Confirm it is unchanged.
- Read-only verification: `codex/.codex/hooks/atomic-commits.sh`
  - Responsibility: existing atomic commit enforcement. Keep its TOML registration unchanged.
- Test: `codex/.codex/tests/test-atomic-commits-hook.sh`
  - Responsibility: baseline and regression test for the existing atomic-commit hook.

## Task 1: Install Context Mode Globally

**Files:**
- No repository file changes.
- External install target: npm global package store.

- [ ] **Step 1: Verify the command is not already available or record the existing install**

Run:

```bash
command -v context-mode
```

Expected before first install: exit code `1` and no output.

Acceptable if already installed: exit code `0` with a path such as `/home/benkim0414/.local/share/mise/installs/node/.../bin/context-mode`. If already installed, continue to Step 3.

- [ ] **Step 2: Install the package globally**

Run:

```bash
npm install -g context-mode
```

Expected: npm completes successfully and prints a package install summary. If the command fails because of network or global install permissions, rerun it with Codex approval escalation.

- [ ] **Step 3: Verify the executable is now available**

Run:

```bash
command -v context-mode
```

Expected: exit code `0` and a path to the `context-mode` executable.

- [ ] **Step 4: Run context-mode diagnostics**

Run:

```bash
context-mode doctor
```

Expected: the command runs and reports diagnostic checks. If any check fails, capture the failing check text and fix that concrete runtime issue before continuing.

- [ ] **Step 5: Confirm no repo files changed during package install**

Run:

```bash
git status --short
```

Expected: no output, because the global package install should not modify this repository.

## Task 2: Add Context Mode MCP Server to Codex Base Config

**Files:**
- Modify: `codex/.codex/config.base.toml`
- Generated local-only after later task: `codex/.codex/config.toml`

- [ ] **Step 1: Write the failing config check**

Run:

```bash
rg -n '^\[mcp_servers\.context-mode\]|^command = "context-mode"$' codex/.codex/config.base.toml
```

Expected before implementation: exit code `1` and no output, because the MCP server is not registered yet.

- [ ] **Step 2: Add the MCP server block**

Use `apply_patch` to insert this block after the existing `[[hooks.PreToolUse.hooks]]` block and before `[marketplaces.superpowers-marketplace]`:

```toml
[mcp_servers.context-mode]
# Launch context-mode as a Codex MCP server.
command = "context-mode"
```

The surrounding section in `codex/.codex/config.base.toml` should become:

```toml
[[hooks.PreToolUse.hooks]]
type = "command"
command = 'bash "$HOME/.codex/hooks/atomic-commits.sh"'
timeout = 10
statusMessage = "Checking atomic commit workflow"

[mcp_servers.context-mode]
# Launch context-mode as a Codex MCP server.
command = "context-mode"

[marketplaces.superpowers-marketplace]
# Load the Superpowers plugin marketplace from its Git repository.
source = "https://github.com/obra/superpowers-marketplace.git"
```

- [ ] **Step 3: Run the config check again**

Run:

```bash
rg -n '^\[mcp_servers\.context-mode\]|^command = "context-mode"$' codex/.codex/config.base.toml
```

Expected: two matching lines, one for `[mcp_servers.context-mode]` and one for `command = "context-mode"`.

- [ ] **Step 4: Confirm the existing atomic hook registration remains**

Run:

```bash
rg -n 'atomic-commits\.sh|Checking atomic commit workflow|^\[\[hooks\.PreToolUse\]\]' codex/.codex/config.base.toml
```

Expected: matches for the `PreToolUse` hook, `atomic-commits.sh`, and `Checking atomic commit workflow`.

- [ ] **Step 5: Commit the MCP config change**

Run:

```bash
git add codex/.codex/config.base.toml
git diff --cached -- codex/.codex/config.base.toml
git commit -m "feat(codex): register context-mode mcp"
```

Expected: commit succeeds with only `codex/.codex/config.base.toml` staged.

## Task 3: Add Upstream Codex Hooks JSON

**Files:**
- Create: `codex/.codex/hooks.json`
- Read-only: `codex/.codex/AGENTS.md`

- [ ] **Step 1: Write the failing hook-file check**

Run:

```bash
test -f codex/.codex/hooks.json
```

Expected before implementation: exit code `1`, because the file does not exist yet.

- [ ] **Step 2: Create `codex/.codex/hooks.json`**

Use `apply_patch` to create this exact file:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "local_shell|shell|shell_command|exec_command|Bash|Shell|apply_patch|Edit|Write|grep_files|ctx_execute|ctx_execute_file|ctx_batch_execute|ctx_fetch_and_index|ctx_search|ctx_index|mcp__",
        "hooks": [
          {
            "type": "command",
            "command": "context-mode hook codex pretooluse"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "context-mode hook codex posttooluse"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "context-mode hook codex sessionstart"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "context-mode hook codex precompact"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "context-mode hook codex userpromptsubmit"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "context-mode hook codex stop"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Validate JSON syntax**

Run:

```bash
jq empty codex/.codex/hooks.json
```

Expected: exit code `0` and no output.

- [ ] **Step 4: Verify every expected context-mode hook command is present**

Run:

```bash
rg -n 'context-mode hook codex (pretooluse|posttooluse|sessionstart|precompact|userpromptsubmit|stop)' codex/.codex/hooks.json
```

Expected: six matching lines, one for each hook command.

- [ ] **Step 5: Confirm `AGENTS.md` is unchanged by this task**

Run:

```bash
git diff -- codex/.codex/AGENTS.md
```

Expected: no output.

- [ ] **Step 6: Commit the hook file**

Run:

```bash
git add codex/.codex/hooks.json
git diff --cached -- codex/.codex/hooks.json
git commit -m "feat(codex): add context-mode hooks"
```

Expected: commit succeeds with only `codex/.codex/hooks.json` staged.

## Task 4: Regenerate Local Codex Config

**Files:**
- Generated local-only: `codex/.codex/config.toml`
- Read-only source: `codex/.codex/config.base.toml`

- [ ] **Step 1: Regenerate config from the worktree base config**

Run from `/home/benkim0414/workspace/dotfiles/.worktrees/context-mode-codex`:

```bash
DOTFILES=/home/benkim0414/workspace/dotfiles/.worktrees/context-mode-codex bin/.local/bin/codex-sync
```

Expected: no output and exit code `0`.

- [ ] **Step 2: Verify generated config contains context-mode MCP server**

Run:

```bash
rg -n '^\[mcp_servers\.context-mode\]|^command = "context-mode"$' codex/.codex/config.toml
```

Expected: two matching lines in `codex/.codex/config.toml`.

- [ ] **Step 3: Verify generated config is still ignored**

Run:

```bash
git status --short --ignored codex/.codex/config.toml
```

Expected:

```text
!! codex/.codex/config.toml
```

- [ ] **Step 4: Confirm no commit is needed for generated config**

Run:

```bash
git status --short
```

Expected: no output if Tasks 2 and 3 were committed, because `config.toml` is ignored.

## Task 5: Full Verification and Final Commit Check

**Files:**
- Verify: `codex/.codex/config.base.toml`
- Verify: `codex/.codex/hooks.json`
- Verify: `codex/.codex/AGENTS.md`
- Verify: `codex/.codex/tests/test-atomic-commits-hook.sh`

- [ ] **Step 1: Run existing atomic-commit regression tests**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: all lines start with `ok denied:` or `ok allowed:` and the command exits `0`.

- [ ] **Step 2: Validate hooks JSON again**

Run:

```bash
jq empty codex/.codex/hooks.json
```

Expected: no output and exit code `0`.

- [ ] **Step 3: Verify context-mode diagnostics after config files exist**

Run:

```bash
context-mode doctor
```

Expected: command exits `0` or prints diagnostic output that identifies no blocking install/config failures. If it exits nonzero, inspect the failing check and fix that concrete issue before continuing.

- [ ] **Step 4: Confirm `AGENTS.md` has no diff**

Run:

```bash
git diff -- codex/.codex/AGENTS.md
```

Expected: no output.

- [ ] **Step 5: Confirm the branch contains the intended commits**

Run:

```bash
git log --oneline main..HEAD
```

Expected: at least these commits are listed:

```text
feat(codex): add context-mode hooks
feat(codex): register context-mode mcp
docs(codex): design context-mode setup
```

- [ ] **Step 6: Confirm final working tree state**

Run:

```bash
git status --short
```

Expected: no output.

## Task 6: Apply Generated Config to the Primary Checkout

**Files:**
- Generated local-only in primary checkout: `/home/benkim0414/workspace/dotfiles/codex/.codex/config.toml`

- [ ] **Step 1: Return to the primary checkout after the branch is merged or checked out there**

Run:

```bash
cd /home/benkim0414/workspace/dotfiles
git branch --show-current
```

Expected: the branch that contains the context-mode config is checked out or merged into the branch you want to use for live dotfiles.

- [ ] **Step 2: Regenerate the live ignored Codex config**

Run:

```bash
bin/.local/bin/codex-sync
```

Expected: no output and exit code `0`.

- [ ] **Step 3: Verify the primary generated config contains context-mode**

Run:

```bash
rg -n '^\[mcp_servers\.context-mode\]|^command = "context-mode"$' codex/.codex/config.toml
```

Expected: two matching lines in the primary checkout's generated `config.toml`.

- [ ] **Step 4: Verify primary generated config remains ignored**

Run:

```bash
git status --short --ignored codex/.codex/config.toml
```

Expected:

```text
!! codex/.codex/config.toml
```

- [ ] **Step 5: Restart Codex CLI**

End the current Codex process and start a new Codex CLI session after the config has been regenerated and stowed.

Expected: the new Codex session starts with the updated MCP and hooks configuration available.
