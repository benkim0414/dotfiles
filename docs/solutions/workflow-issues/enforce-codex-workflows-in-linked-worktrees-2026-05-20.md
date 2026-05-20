---
title: "Enforce Codex workflows in linked git worktrees"
date: "2026-05-20"
category: "workflow-issues"
module: "dotfiles/codex"
problem_type: "workflow_issue"
component: "development_workflow"
severity: "high"
applies_when:
  - "Codex workflows may create artifacts or code changes from a primary checkout"
  - "Superpowers or Compound Engineering automation needs consistent worktree isolation"
  - "Hook-level enforcement must prevent shell and MCP bypasses"
related_components:
  - "tooling"
  - "assistant"
  - "documentation"
tags:
  - "codex"
  - "worktrees"
  - "hooks"
  - "compound-engineering"
  - "superpowers"
  - "workflow-enforcement"
  - "mcp"
  - "security-review"
---

# Enforce Codex workflows in linked git worktrees

## Context

Codex needed a durable guardrail that makes linked worktrees the default
mutation boundary for agent work. The user workflow creates artifacts through
Superpowers and Compound Engineering, including brainstorm specs,
implementation plans, solution docs, code, config, and test changes. Those
artifacts must be created in the feature worktree, not in the primary checkout.

Instruction-only guidance was not enough. Codex can write through direct edit
tools, shell commands, shell redirection, Git subcommands, MCP executors, and
nested context-mode batch commands. The solved pattern was a global Codex
`PreToolUse` hook that allows read-only inspection, preserves a recovery command
for creating a linked worktree, and denies write-capable operations that target a
repository's primary checkout from any origin.

Session history search found no relevant prior sessions for this specific
problem, so the documented guidance comes from the implemented branch and review
findings.

## Guidance

Enforce worktree isolation at the hook layer, not only in workflow prose. Treat
the hook as a conservative command and target classifier: if a command is
write-capable and the target cannot be proven safe, deny it.

Wire the guard globally through Codex config so it applies in every repository:

```toml
[[hooks.PreToolUse]]
matcher = "local_shell|shell|shell_command|exec_command|Bash|Shell|apply_patch|Edit|Write|grep_files|ctx_execute|ctx_execute_file|ctx_batch_execute|ctx_fetch_and_index|ctx_search|ctx_index|mcp__"

[[hooks.PreToolUse.hooks]]
type = "command"
command = 'bash "$HOME/.codex/hooks/worktree-guard.sh"'
timeout = 10
statusMessage = "Checking worktree isolation"
```

The guard should:

- Detect whether the current repository checkout is a linked worktree by
  comparing `git rev-parse --absolute-git-dir` with
  `git rev-parse --git-common-dir`.
- Canonicalize paths before deciding whether a target is inside a primary
  checkout or linked worktree.
- Allow read-only inspection commands in a primary checkout.
- Allow ordinary writes inside the active linked worktree.
- Deny writes into a primary checkout from a primary checkout, a sibling linked
  worktree, or an outside directory.
- Inspect direct tool target fields, `apply_patch` patch headers, shell command
  text, MCP executor payloads, and nested
  `ctx_batch_execute.commands[].command` entries.
- Preserve an explicit recovery path such as
  `git worktree add .worktrees/<slug> -b <branch>` so enforcement does not trap
  the user in a primary checkout.
- Keep the generated config in sync with the live Codex config via `codex-sync`.

Use a denial reason that explains both the problem and the recovery path:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Writes to the main worktree are blocked. Use git worktree add .worktrees/<slug> -b <branch>."
  }
}
```

## Why This Matters

Agent workflows can mutate repositories through surfaces that look read-oriented
or indirect:

- Shell redirects: `printf 'x' > generated.txt`
- Git output flags: `git diff --output=generated.diff`
- Git branch mutation: `git branch feature`
- In-place tools: `sed -i`, `find -fprint`, `find -fprintf`, `find -fls`
- Helper execution: `rg --pre`
- Relative path escapes from outside a repo or from a sibling worktree
- Shell directory changes: `cd ../primary; touch generated.txt`
- Shell variable indirection: `p=../primary; touch "$p/generated.txt"`
- MCP executor payloads and nested `ctx_batch_execute` command arrays

A guard that only checks the current directory misses commands that target the
primary checkout from elsewhere. A guard that only blocks direct edit tools
misses shell and MCP execution. A guard that treats command names as read-only
without checking write-capable flags creates bypasses. The reliable pattern is
path-aware, command-aware, and fail-closed around ambiguous shell control.

## When to Apply

- Use this pattern when Codex or other agents should keep a stable primary
  checkout and do all feature work in disposable linked worktrees.
- Use it when workflow tools generate plans, specs, docs, tests, or code before
  implementation begins.
- Use it when MCP tools can execute shell-like payloads or batch command arrays.
- Use it when dotfiles generate global Codex config that must be safe across
  arbitrary downstream repositories.
- Do not treat this as a hostile-code sandbox. It is a workflow safety guard for
  trusted developer machines and trusted agent sessions.

## Examples

Allow read-only inspection in a primary checkout:

```bash
git status --short
git diff -- README.md
git branch --show-current
sed -n '1,20p' README.md
rg -n fixture README.md
```

Allow recovery from a primary checkout:

```bash
git worktree add .worktrees/recovery -b recovery-branch
```

Block direct writes in a primary checkout:

```bash
touch generated.txt
printf 'blocked\n' > generated.txt
git add README.md
```

Block write-capable commands that look like inspection:

```bash
git diff --output=generated.diff
git show --output=generated.txt HEAD:README.md
sed -n -i '1p' README.md
find . -name README.md -fprint generated.txt
rg --pre touch fixture README.md
```

Block writes back into the primary checkout from a linked worktree or outside
directory:

```bash
touch ../primary/relative-generated.txt
git -C ../primary branch feature
p=../primary; touch "$p/linked-indirect-generated.txt"
cd ../primary; touch linked-cd-generated.txt
pushd ../primary; touch linked-pushd-generated.txt
```

Inspect nested MCP payloads as executable surfaces:

```json
{
  "tool_name": "mcp__context_mode__.ctx_batch_execute",
  "tool_input": {
    "commands": [
      {
        "label": "write",
        "command": "touch ../primary/mcp-batch-relative-generated.txt"
      }
    ]
  }
}
```

Regression tests should include both allowed and denied cases for:

- Direct edit tools: `Write`, `apply_patch`
- Shell mutation: redirects, `touch`, `git add`
- Git mutation: branch creation, forced branch updates, output-writing flags
- Command flags that mutate: `sed -i`, `find -delete`, `find -fprint`,
  `rg --pre`
- Path escapes: absolute paths, relative paths, `$HOME`, quoted paths, variables
- Directory changes: `cd`, `cd ../primary/`, `pushd`
- Linked worktree writes back to primary checkout
- MCP executors and nested batch command payloads
- Recovery command remains allowed

## Related

- [Superpowers + compound-engineering workflow reorganization](superpowers-workflow-reorg-2026-05-19.md)
- [Configure context-mode for Codex CLI](../tooling-decisions/configure-context-mode-for-codex-cli-2026-05-17.md)
- [Inherit scoped Codex approvals in subagents](inherit-scoped-codex-approvals-in-subagents-2026-05-19.md)
- Implementation: `codex/.codex/hooks/worktree-guard.sh`
- Wiring: `codex/.codex/config.base.toml`, `bin/.local/bin/codex-sync`
- Tests: `codex/.codex/tests/test-worktree-guard-hook.sh`,
  `codex/.codex/tests/test-codex-sync-hooks.sh`
