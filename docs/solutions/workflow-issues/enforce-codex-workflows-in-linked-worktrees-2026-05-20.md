---
title: "Enforce Codex workflows in linked git worktrees"
date: "2026-05-20"
last_updated: "2026-05-20"
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
- Prefer the effective tool workdir from the hook payload when Codex provides
  one, because the hook process `cwd` can differ from the shell command's
  requested execution directory.
- Canonicalize paths before deciding whether a target is inside a primary
  checkout or linked worktree.
- Allow read-only inspection commands in a primary checkout.
- Allow ordinary writes inside the active linked worktree.
- Allow non-repository scratch writes, such as `touch /tmp/<file>`, when they do
  not target any Git worktree.
- Deny writes into a primary checkout from a primary checkout, a sibling linked
  worktree, or an outside directory.
- Resolve explicit Git target selectors before classifying the command:
  `git -C <path>`, `git --work-tree <path>`, and `git --git-dir <path>`.
- Parse command words with enough shell awareness to preserve quoted paths with
  spaces. Simple whitespace splitting is not safe for guard decisions.
- Validate explicit `--git-dir` values against the selected worktree's own
  `git rev-parse --absolute-git-dir`. A linked `--work-tree` paired with the
  primary repo's `.git` directory can still mutate the primary index and must be
  denied.
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

A guard that trusts only the hook process `cwd` also creates false positives.
Codex can invoke a shell tool with an effective `workdir` inside a linked
worktree while the hook payload still appears rooted at the repository's primary
checkout. In that case, blocking `git add`, `git update-index`, `git apply
--cached`, or `git hash-object -w` prevents the intended isolated workflow.

The inverse is just as important: Git command options can redirect mutations
away from the apparent shell cwd. `git -C`, `--work-tree`, and `--git-dir` must
be interpreted as part of the target calculation. In particular, `--git-dir`
controls which index Git mutates; a command whose `--work-tree` points at a
linked worktree but whose `--git-dir` points at the primary checkout is still a
primary-worktree mutation.

## When to Apply

- Use this pattern when Codex or other agents should keep a stable primary
  checkout and do all feature work in disposable linked worktrees.
- Use it when workflow tools generate plans, specs, docs, tests, or code before
  implementation begins.
- Use it when MCP tools can execute shell-like payloads or batch command arrays.
- Use it when dotfiles generate global Codex config that must be safe across
  arbitrary downstream repositories.
- Use it when hook payload metadata can contain both a session/root directory
  and a tool-specific execution directory.
- Use it when Git commands may use explicit target selectors such as `-C`,
  `--work-tree`, or `--git-dir`.
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

Allow writes when the tool's effective workdir or explicit Git target is a
linked worktree:

```bash
git add README.md docs/github-issues.md
git -C "/path/with spaces/repo/.worktrees/feature" add README.md
git --git-dir "/path/repo/.git/worktrees/feature" add README.md
```

Allow scratch writes that do not target any Git repository:

```bash
touch /tmp/worktree-guard-scratch
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

Block explicit Git target selectors that point at the primary checkout or its
index, even when the shell command starts from a linked worktree:

```bash
git -C "/path/repo" add README.md
git --work-tree "/path/repo" add README.md
git --git-dir "/path/repo/.git" --work-tree "/path/repo/.worktrees/feature" add README.md
```

Do not over-correct by denying matching linked git directories:

```bash
git --git-dir "/path/repo/.git/worktrees/feature" add README.md
git --git-dir "/path/repo/.git/worktrees/feature" --work-tree "/path/repo/.worktrees/feature" add README.md
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
- Effective tool workdir fields: `workdir`, `cwd`, or
  `current_working_directory` when present in the hook payload
- Git target selectors: `git -C`, `--work-tree`, `--git-dir`, quoted paths with
  spaces, mismatched primary git dirs, and matching linked git dirs
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
