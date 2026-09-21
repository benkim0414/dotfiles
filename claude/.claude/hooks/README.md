# Claude Code Hooks

Four shell hooks enforcing three things: worktree isolation, atomic commits,
and conventional commit scope. Nothing else. They are registered in
`claude/.claude/settings.base.json` under `hooks` (merged with
`settings.overlay.json` by `claude-sync` into `~/.claude/settings.json`). The
`claude` package stows to `~/.claude/`, so each hook runs as
`bash $HOME/.claude/hooks/<name>.sh`.

## Conventions

- **Shebang:** `#!/usr/bin/env bash`. A deliberate deviation from Google Shell
  Style Guide §2 (`#!/bin/bash`): macOS ships bash 3.2 at `/bin/bash` while
  Homebrew bash 5 lives elsewhere. Registrations name the interpreter, so the
  shebang is never consulted at runtime -- **every hook must be bash 3.2
  syntax regardless**.
- **Exit codes:** PreToolUse `exit 0` = allow, `exit 2` = block (stderr shown
  to Claude). SessionStart and PostToolUse emit structured JSON and must not
  block.
- **Style:** Google Shell Style Guide, `shfmt -i 2 -ci -bn`,
  `shellcheck --severity=warning`.

## The hooks

| Hook | Event | Matcher | Purpose | Exit |
| --- | --- | --- | --- | --- |
| `arm-worktree-guard.sh` | SessionStart | n/a | write `pending-<session-id>`; sweep markers older than 24h | 0 |
| `commit-guard.sh` | PreToolUse | `Bash` | block `git add -A/--all/--update/.` and `git commit -a`; block commit on main; warn on bad commit scope | 0 / 2 |
| `worktree-guard.sh` | PreToolUse | `Write\|Edit\|NotebookEdit` | block edits inside the repo until `EnterWorktree()` | 0 / 2 |
| `worktree-entered.sh` | PostToolUse | `EnterWorktree` | remove the marker | 0 |

## Worktree isolation is three files

`arm-worktree-guard.sh` writes `~/.claude/session-worktrees/pending-<id>`,
`worktree-guard.sh` blocks while it exists, `worktree-entered.sh` removes it.
**The arming hook is the only writer of that marker.** Deleting it leaves the
guard registered, its tests passing, and nothing enforced --
`tests/arm-worktree-guard/cases/00-arms-in-main-checkout.sh` exists to catch
exactly that.

Escape hatch: `rm ~/.claude/session-worktrees/pending-<id>`, printed in the
block message.

## Shared libraries (`../lib/`)

| Lib | Role | Key functions |
| --- | --- | --- |
| `session.sh` | session id, marker path, worktree detection, context emit | `emit_context`, `emit_context_with_msg`, `parse_session_id`, `pending_file`, `check_worktree_pending`, `cwd_repo_hint`, `worktree_kind` |
| `commit-scope.sh` | commit-scope signals S1-S4 | `is_banned_scope`, `suggest_scope` |
| `portability.sh` | bash 3.2 / cross-platform helpers | `file_mtime`, `to_lower` |

`to_lower` currently has no caller. It stays as the documented landing spot
for the next hook that needs lowercasing, because `${x,,}` fails silently
under bash 3.2.

## Tests (`../tests/`)

Each suite iterates `cases/*.sh` and exits non-zero on any failure:

```sh
cd claude/.claude/tests/<suite> && bash run.sh
```

| Suite | Covers |
| --- | --- |
| `commit-scope/` | `lib/commit-scope.sh` + `commit-guard.sh` |
| `worktree-guard/` | `worktree-guard.sh` block and allow branches |
| `arm-worktree-guard/` | `arm-worktree-guard.sh` marker writing and sweeping |
| `session-lib/` | `lib/session.sh` (and `portability.sh`, which it sources) |

`settings.base.json` is the source of truth for matchers; the table above is
documentation.
