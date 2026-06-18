# Agentmemory Codex Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install agentmemory for Codex through the supported Codex plugin path and persist the stable dotfiles configuration.

**Architecture:** Use Codex's plugin marketplace commands to install `agentmemory@agentmemory`, then inspect the generated config changes before deciding what belongs in the checked-in base config. Keep `context-mode` untouched, avoid manual cache paths, and defer explicit hook fallback unless plugin verification proves it is needed.

**Tech Stack:** Codex CLI plugin platform, TOML config under `codex/.codex/`, Git linked worktree, optional `agentmemory` / `npx @agentmemory/agentmemory` runtime verification.

## Global Constraints

- Do not replace context-mode with agentmemory.
- Do not add manual MCP-only wiring unless the plugin path fails and the user explicitly approves the fallback.
- Do not add absolute hook script paths into checked-in config.
- Do not configure remote agentmemory credentials or secrets in the repository.
- Do not change Codex approval policy, auto-review policy, or unrelated hooks.
- Do not touch or revert `codex/.codex/hooks/worktree-guard.sh`.
- Request approval for plugin install commands if network access or writes outside the workspace are required.

---

## File Structure

- Modify: `codex/.codex/config.toml`
  - Active Codex config snapshot. Expected to receive generated marketplace/plugin metadata from `codex plugin` commands.
- Modify: `codex/.codex/config.base.toml`
  - Durable checked-in source for reproducible Codex config. Add only stable marketplace/plugin entries that should survive regeneration.
- No change: `codex/.codex/hooks/worktree-guard.sh`
  - Existing unrelated user change in the main checkout; leave untouched.
- No change unless explicitly approved later: global `~/.codex/hooks.json`
  - Only relevant for the deferred `agentmemory connect codex --with-hooks` fallback.

## Task 1: Install Agentmemory Through Codex Plugin Commands

**Files:**
- Modify: `codex/.codex/config.toml`
- Do not modify: `codex/.codex/config.base.toml`
- Do not modify: `codex/.codex/hooks/worktree-guard.sh`

**Interfaces:**
- Consumes: existing Codex CLI plugin support and user-approved network/filesystem access when required.
- Produces: installed local marketplace entry for `agentmemory` and enabled plugin entry for `agentmemory@agentmemory` in the active Codex config.

- [ ] **Step 1: Capture the pre-install config state**

Run:

```bash
git status --short
git diff -- codex/.codex/config.toml codex/.codex/config.base.toml codex/.codex/hooks/worktree-guard.sh
codex plugin marketplace list
codex plugin list
```

Expected:

- `git status --short` shows no changes in this linked worktree except plan/spec work already committed.
- `git diff -- ...` prints no diff for the three listed config/hook paths.
- `codex plugin marketplace list` includes the existing Superpowers and Compound Engineering marketplaces.
- `codex plugin list` does not yet list `agentmemory@agentmemory` as installed.

- [ ] **Step 2: Add the agentmemory marketplace**

Run:

```bash
codex plugin marketplace add rohitg00/agentmemory --json
```

Expected:

- If sandbox/network restrictions block the command, rerun the same command with an approval request.
- Command exits `0`.
- JSON output names a marketplace derived from `agentmemory` and records the Git source `rohitg00/agentmemory`.

- [ ] **Step 3: Install the agentmemory plugin**

Run:

```bash
codex plugin add agentmemory@agentmemory --json
```

Expected:

- If sandbox/network restrictions block the command, rerun the same command with an approval request.
- Command exits `0`.
- JSON output confirms `agentmemory@agentmemory` installed or enabled.

- [ ] **Step 4: Inspect active config changes**

Run:

```bash
git diff -- codex/.codex/config.toml codex/.codex/config.base.toml codex/.codex/hooks/worktree-guard.sh
codex plugin marketplace list
codex plugin list
```

Expected:

- `codex/.codex/config.toml` contains a new `[marketplaces.agentmemory]` or equivalent marketplace entry.
- `codex/.codex/config.toml` contains `[plugins."agentmemory@agentmemory"]` with `enabled = true`.
- `codex/.codex/config.base.toml` is unchanged at this task.
- `codex/.codex/hooks/worktree-guard.sh` is unchanged.
- `codex plugin list` reports `agentmemory@agentmemory`.

- [ ] **Step 5: Commit active install snapshot**

Only if `codex/.codex/config.toml` changed and the diff contains no secrets or unrelated changes, run:

```bash
git add codex/.codex/config.toml
git diff --cached -- codex/.codex/config.toml
git commit -m "feat(codex): install agentmemory plugin"
```

Expected:

- The cached diff contains only the agentmemory marketplace/plugin install metadata.
- Commit succeeds.

## Task 2: Persist Stable Base Config Entries

**Files:**
- Modify: `codex/.codex/config.base.toml`
- Inspect: `codex/.codex/config.toml`
- Do not modify: `codex/.codex/hooks/worktree-guard.sh`

**Interfaces:**
- Consumes: generated active config entries from Task 1.
- Produces: stable base config entries for future dotfiles regeneration.

- [ ] **Step 1: Compare plugin patterns already in base config**

Run:

```bash
sed -n '/\\[marketplaces\\.superpowers-marketplace\\]/,/\\[otel\\]/p' codex/.codex/config.base.toml
sed -n '/\\[marketplaces\\.agentmemory\\]/,/\\[plugins\\."agentmemory@agentmemory"\\]/p' codex/.codex/config.toml
```

Expected:

- Existing base config marketplace entries use `source` and `source_type`.
- Generated active config may also include `last_updated` and `last_revision`; those generated fields should not be copied to base unless they match the existing base pattern.

- [ ] **Step 2: Add the stable marketplace entry to base config**

Edit `codex/.codex/config.base.toml` so the marketplace section includes:

```toml
[marketplaces.agentmemory]
# Load the Agentmemory plugin marketplace from its Git repository.
source = "https://github.com/rohitg00/agentmemory.git"
# Tell Codex to treat the marketplace source as a Git checkout.
source_type = "git"
```

Place it near the other `[marketplaces.*]` entries.

- [ ] **Step 3: Add the stable plugin enablement to base config**

Edit `codex/.codex/config.base.toml` so the plugin section includes:

```toml
[plugins."agentmemory@agentmemory"]
enabled = true
```

Place it near the other `[plugins.*]` entries.

- [ ] **Step 4: Verify base config diff is scoped**

Run:

```bash
git diff -- codex/.codex/config.base.toml codex/.codex/hooks/worktree-guard.sh
```

Expected:

- `codex/.codex/config.base.toml` adds only the `agentmemory` marketplace and plugin entries.
- `codex/.codex/hooks/worktree-guard.sh` has no diff in this linked worktree.

- [ ] **Step 5: Commit base config**

Run:

```bash
git add codex/.codex/config.base.toml
git diff --cached -- codex/.codex/config.base.toml
git commit -m "feat(codex): persist agentmemory plugin config"
```

Expected:

- The cached diff contains only the stable base config entries.
- Commit succeeds.

## Task 3: Verify Agentmemory Availability Without Hook Fallback

**Files:**
- Inspect: `codex/.codex/config.toml`
- Inspect: `codex/.codex/config.base.toml`
- Do not modify: `codex/.codex/hooks/worktree-guard.sh`
- Do not modify: `~/.codex/hooks.json`

**Interfaces:**
- Consumes: installed plugin and base config from Tasks 1 and 2.
- Produces: verification evidence that the plugin is installed, visible to Codex, and does not require manual hook fallback for this implementation.

- [ ] **Step 1: Confirm Codex sees the installed plugin**

Run:

```bash
codex plugin marketplace list
codex plugin list
```

Expected:

- Marketplace list includes agentmemory.
- Plugin list includes `agentmemory@agentmemory`.

- [ ] **Step 2: Check available agentmemory runtime commands**

Run:

```bash
command -v agentmemory || true
agentmemory --help || true
```

Expected:

- If `agentmemory` is installed, `agentmemory --help` prints command usage and exits `0`.
- If `agentmemory` is not installed, the first command prints nothing and the second command fails with `command not found`; this is acceptable because runtime server installation is separate from Codex plugin config.

- [ ] **Step 3: Check npx runtime help without starting a long-lived server**

Run:

```bash
npx -y @agentmemory/agentmemory --help
```

Expected:

- If network/package access is available, command exits `0` and prints usage.
- If network access is blocked, record the failure and request approval only if this check is needed to decide whether the plugin install succeeded.
- Do not start a persistent server as part of this verification task unless the user explicitly asks for it.

- [ ] **Step 4: Confirm no fallback hook config was added**

Run:

```bash
git diff -- codex/.codex/hooks/worktree-guard.sh
test ! -f "$HOME/.codex/hooks.json" || sed -n '/agentmemory/Ip' "$HOME/.codex/hooks.json"
```

Expected:

- The repo hook file has no diff.
- The global hooks file either does not exist or has no newly added agentmemory fallback block from this work.

- [ ] **Step 5: Final diff and status check**

Run:

```bash
git status --short
git log --oneline -3
```

Expected:

- `git status --short` is clean in the linked worktree.
- Recent commits include the design spec, active install snapshot if changed, and base config persistence commit.

## Self-Review

- Spec coverage: Task 1 covers official plugin install and active config inspection; Task 2 covers stable base config persistence; Task 3 covers plugin visibility, runtime availability, no fallback hooks, and no `worktree-guard.sh` edits.
- Placeholder scan: passed; the plan contains no deferred-work markers or vague edge-case instructions.
- Type consistency: config table names are consistent across tasks: `[marketplaces.agentmemory]` and `[plugins."agentmemory@agentmemory"]`.
