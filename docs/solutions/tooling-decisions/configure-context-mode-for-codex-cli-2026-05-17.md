---
title: "Configure context-mode for Codex CLI"
date: "2026-05-17"
category: "tooling-decisions"
module: "dotfiles/codex"
problem_type: "tooling_decision"
component: "tooling"
severity: "low"
applies_when:
  - "Codex CLI should use context-mode as an MCP server"
  - "Dotfiles need tracked Codex hook configuration while live ~/.codex files may have stow conflicts"
  - "Ignored generated Codex config must be regenerated from tracked base config"
symptoms:
  - "Codex CLI context-mode integration is not represented in dotfiles"
  - "Stow cannot directly own a new ~/.codex/hooks.json because existing live files are not all symlinks"
root_cause: "incomplete_setup"
resolution_type: "tooling_addition"
related_components:
  - "development_workflow"
  - "assistant"
tags:
  - "codex-cli"
  - "context-mode"
  - "mcp"
  - "hooks"
  - "stow"
---

# Configure context-mode for Codex CLI

## Context

`context-mode` can be installed for Codex CLI by following the upstream Codex
setup, but this dotfiles repo has an important split between durable source
config and generated live config.

Durable Codex settings belong in `codex/.codex/config.base.toml`. The ignored
`codex/.codex/config.toml` is produced by `bin/.local/bin/codex-sync`, so it is
not the source of truth. Hand-editing the generated file is fragile because the
next `codex-sync` run can overwrite it.

The existing atomic commit workflow uses a TOML `PreToolUse` hook in
`config.base.toml`. The upstream `context-mode` setup uses
`$CODEX_HOME/hooks.json` for hook wiring. Adding `context-mode` should therefore
preserve the existing TOML hook instead of replacing it.

The chosen setup was:

- Install `context-mode` globally with npm.
- Register `context-mode` as a Codex MCP server in `config.base.toml`.
- Use tracked `codex/.codex/hooks.json` for upstream Codex hook registration.
- Leave `codex/.codex/AGENTS.md` unchanged.
- Regenerate the ignored Codex config with `codex-sync`.
- Wire the live `~/.codex/hooks.json` path to the tracked hook file.

Session history search found no relevant prior sessions for this specific
context-mode/Codex setup.

## Guidance

Install the package globally:

```sh
npm install -g context-mode
```

Add the MCP server declaration to `codex/.codex/config.base.toml`, not directly
to the generated `config.toml`:

```toml
[mcp_servers.context-mode]
# Launch context-mode as a Codex MCP server.
command = "context-mode"
```

Create `codex/.codex/hooks.json` with upstream-style Codex hook registrations.
The important shape is a top-level `hooks` object with the Codex events and
`context-mode hook codex <event>` commands:

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

Regenerate the ignored live config from the primary checkout:

```sh
bin/.local/bin/codex-sync
```

When working from a feature worktree, point `DOTFILES` at that worktree so the
script does not write into the primary checkout:

```sh
DOTFILES=/home/benkim0414/workspace/dotfiles/.worktrees/context-mode-codex bin/.local/bin/codex-sync
```

If regular `stow -t ~ codex` fails because existing live files under
`~/.codex/` are not symlinks, do not use `--adopt` casually. In this setup, only
the new hook file needed live wiring:

```sh
~/.codex/hooks.json -> ../workspace/dotfiles/codex/.codex/hooks.json
```

## Why This Matters

Keeping the MCP server in `config.base.toml` makes the setup reproducible. The
generated `config.toml` stays local and ignored, which avoids committing Codex
runtime state such as plugin notices, trust entries, and local UI state.

Keeping `context-mode` hooks in `hooks.json` follows upstream Codex guidance
without disturbing the existing TOML `PreToolUse` atomic-commit hook. This lets
both hook systems coexist: context-mode handles MCP/session tracking, while the
existing hook keeps enforcing atomic commit behavior.

The source/live split also makes `context-mode doctor` failures easier to
diagnose. Check the durable source first, then the generated config, then the
live `$CODEX_HOME` path:

```sh
jq empty codex/.codex/hooks.json
rg -n '^\[mcp_servers\.context-mode\]|^command = "context-mode"$' \
  codex/.codex/config.base.toml codex/.codex/config.toml
ls -l ~/.codex/hooks.json
context-mode doctor
```

`context-mode doctor` may fail before both live hooks and generated config are
wired. A sandboxed run can also report a server-test failure even when the live
setup works; run it outside the sandbox for final verification.

## When to Apply

Use this pattern when configuring Codex CLI tooling in this dotfiles repo and
the tool requires:

- A Codex MCP server entry.
- A `$CODEX_HOME/hooks.json` hook file.
- Durable settings that must survive `codex-sync`.
- Preservation of existing Codex hooks, especially the atomic commit
  `PreToolUse` hook.

Use the same source-of-truth rule for future Codex config changes: edit
`codex/.codex/config.base.toml`, then run `bin/.local/bin/codex-sync`.

## Examples

Verify the executable:

```sh
command -v context-mode
```

Expected resolved binary in this setup:

```text
/home/benkim0414/.local/share/mise/installs/node/24/bin/context-mode
```

Verify generated config contains the MCP server:

```sh
rg -n '^\[mcp_servers\.context-mode\]|^command = "context-mode"$' \
  codex/.codex/config.base.toml codex/.codex/config.toml
```

Verify the hooks file is parser-safe JSON:

```sh
jq empty codex/.codex/hooks.json
```

Verify the existing atomic commit hook still works:

```sh
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Verify the full live context-mode setup:

```sh
context-mode doctor
```

Final successful diagnostics included:

- Server test: pass.
- Codex hooks feature flag: pass.
- All Codex hooks in `~/.codex/hooks.json`: pass.
- Plugin enabled through `[mcp_servers]`: pass.
- FTS5 / SQLite: pass.
- npm MCP version: pass.

## Related

- [Context-mode Codex design](../../superpowers/specs/2026-05-17-context-mode-codex-design.md)
- [Context-mode Codex implementation plan](../../superpowers/plans/2026-05-17-context-mode-codex.md)
- [Codex atomic commits design](../../superpowers/specs/2026-05-15-codex-atomic-commits-design.md)
- [Codex atomic commits implementation plan](../../superpowers/plans/2026-05-15-codex-atomic-commits.md)
- [Codex worktree Git approval design](../../superpowers/specs/2026-05-15-codex-worktree-git-approval-design.md)
