# Claude Code Hooks

Shell hooks that fire on Claude Code lifecycle and tool events. They are
registered in `claude/.claude/settings.base.json` under `hooks` (deep-merged
with the work overlay by `claude-sync` into `~/.claude/settings.json`). The
`claude` package is stowed to `~/.claude/`, so each hook runs as
`bash $HOME/.claude/hooks/<name>.sh`.

The work overlay (`~/workspace/claude-skills/settings.overlay.json`) may
register additional, work-specific hooks that do **not** live in this repo;
they are out of scope for this README.

## Conventions

- **Shebang:** every hook uses `#!/usr/bin/env bash`. This is a deliberate
  deviation from Google Shell Style Guide §2 (`#!/bin/bash`): macOS ships
  bash 3.2 at `/bin/bash`, while Homebrew bash 5 lives outside `/bin`.
  `env bash` selects the modern bash on both macOS and Linux.
- **Exit codes:** PreToolUse hooks use `exit 0` = allow and `exit 2` = block
  (stderr is shown to Claude). `read-once.sh` instead emits a
  `permissionDecision: "deny"` JSON object to block. PostToolUse / SessionStart
  / PostCompact / etc. emit structured JSON (`additionalContext`,
  `systemMessage`, `permissionDecision`) and must not block.
- **Async hooks** (`audit-log.sh`, `notify.sh`) are registered with
  `"async": true` and must never slow Claude down.
- **Style:** files conform to the Google Shell Style Guide, formatted with
  `shfmt -i 2 -ci -bn` and linted with `shellcheck --severity=warning`.
  Two documented deviations: the `env bash` shebang (above) and
  `read-once.sh` intentionally omits a `main()` wrapper (see its header) so
  its fast-exits can run before it sources its lib — a hot-path optimization.
  Residual `shellcheck` `info` findings (SC1091 for dynamically-pathed
  `source`, one SC2012 `ls` in `read-once.sh`) are inherent and accepted.

## Hooks by event

### SessionStart
| Hook | Purpose | Exit |
| --- | --- | --- |
| `git-session-start.sh` | inject git/worktree context; recover deleted CWDs; auto-checkout merged branches; flag main worktree as needing EnterWorktree() | 0 |

### UserPromptSubmit
| Hook | Purpose | Exit |
| --- | --- | --- |
| `resolve-pr-refs.sh` | inject a PR/issue summary when the prompt references one; clear the tmux attention marker | 0 |

### PreToolUse
| Hook | Matcher | Purpose | Exit |
| --- | --- | --- | --- |
| `read-once.sh` | `Read\|NotebookRead\|mcp__qmd__get\|Bash\|Grep` | block redundant reads already in context (deny JSON) | 0 allow / deny JSON |
| `git-safety.sh` | `Bash` | guard git Bash calls: no commit/push/merge on main; commit scope + atomicity | 0 allow / 2 block |
| `worktree-guard.sh` | `Write\|Edit\|NotebookEdit` | block file edits until EnterWorktree() this session | 0 allow / 2 block |
| `permission-policy.sh` | `Bash\|Write\|Edit\|NotebookEdit\|WebFetch` | semantic permission policy; emits `ask`, never `deny` | 0 |
| `notify.sh` | `AskUserQuestion\|ExitPlanMode` | attention notification (async) | 0 |

### PostToolUse
| Hook | Matcher | Purpose | Exit |
| --- | --- | --- | --- |
| `worktree-entered.sh` | `EnterWorktree` | clear the session's pending-worktree marker | 0 |
| `worktree-exited.sh` | `ExitWorktree` | remind Claude of post-worktree next steps | 0 |
| `audit-log.sh` | mutating + read tools | append a JSONL audit entry (async) | 0 |

`audit-log.sh` full matcher:
`Bash|Write|Edit|NotebookEdit|CronCreate|CronDelete|RemoteTrigger|Read|NotebookRead|Grep|mcp__qmd__get|mcp__qmd__multi_get`.

### PostToolUseFailure
| Hook | Purpose | Exit |
| --- | --- | --- |
| `failure-recovery.sh` | inject recovery guidance on recognized failures (deleted CWD, gh auth, merge conflict, permission denied, timeout) | 0 |

### PostCompact
| Hook | Purpose | Exit |
| --- | --- | --- |
| `restore-git-context.sh` | re-inject git/worktree orientation after a lossy compaction | 0 |

### SessionEnd
| Hook | Purpose | Exit |
| --- | --- | --- |
| `read-once-gc.sh` | prune the ended session's read-once cache + snapshot dir; sweep orphan snapshots | 0 |

### Notification
| Hook | Purpose | Exit |
| --- | --- | --- |
| `notify.sh` | attention notification — Ghostty OSC 777 + tmux bell (also fires on PreToolUse) | 0 |

## Shared libraries (`../lib/`)

Hooks source these via a `../lib/<name>.sh` path resolved from `BASH_SOURCE`.
`settings.base.json` is the source of truth for matchers; the tables above are
documentation.

| Lib | Role | Key functions |
| --- | --- | --- |
| `session.sh` | session id, context emit, worktree/workflow detection | `emit_context`, `emit_context_with_msg`, `parse_session_id`, `pending_file`, `check_worktree_pending`, `cwd_repo_hint`, `worktree_kind`, `workflow_no_pr` |
| `commit-scope.sh` | commit-scope signal validation (S1-S4) | `is_banned_scope`, `suggest_scope` |
| `permission-policy.sh` | permission-policy pattern matchers | `check_bash`, `check_file_edit`, `check_web_fetch` |
| `read-once-cache.sh` | read-once JSONL cache helpers | `rc_record`, `rc_lookup`, `rc_deny`, `rc_recent_touch`, `rc_path_slug` |
| `portability.sh` | cross-platform mtime/timeout | `file_mtime`, `run_timeout` |

## Tests (`../tests/`)

Each suite iterates `cases/*.sh` and exits non-zero on any failure:

```sh
cd claude/.claude/tests/<suite> && bash run.sh
```

| Suite | Covers |
| --- | --- |
| `commit-scope/` | `lib/commit-scope.sh` + `git-safety.sh` commit-scope logic |
| `permission-policy/` | `lib/permission-policy.sh` + `permission-policy.sh` hook |
| `read-once/` | `read-once.sh` hook + `lib/read-once-cache.sh` |
| `session-lib/` | `lib/session.sh` (and `portability.sh`, which it sources) |

Hooks without a dedicated suite — `audit-log`, `failure-recovery`,
`git-session-start`, `notify`, `resolve-pr-refs`, `restore-git-context`,
`read-once-gc`, `worktree-entered`, `worktree-exited` — are verified by
`shellcheck` and manual smoke runs (pipe a representative hook JSON payload to
the script and check the exit code + output).
