# Silence dead Write/NotebookEdit deny-rule warnings

Date: 2026-07-17

## Problem

At Claude Code startup the harness emits warnings like:

```
Permission deny rule (.../.claude/settings.json): Write(**/.env) is not
matched by file permission checks -- only Edit(path) rules are. Use
Edit(**/.env) instead (Edit rules cover all file-editing tools).
```

One warning per `Write(<path>)` and `NotebookEdit(<path>)` deny entry --
12 in total.

## Root cause

Claude Code's file-permission layer matches file-editing tools (Edit,
Write, NotebookEdit) against `Edit(<path>)` rules only. A single
`Edit(<path>)` deny entry already blocks all three tools for that path.
Standalone `Write(<path>)` / `NotebookEdit(<path>)` entries match nothing
-- they are dead rules, and the harness flags each one.

The `deny` block in `claude/.claude/settings.base.json` already carries an
`Edit(<path>)` entry beside every flagged `Write(<path>)`/
`NotebookEdit(<path>)`. So the flagged entries are pure redundancy; the
protection they appear to add is already provided by the `Edit(...)`
entries.

`Bash(<glob>)` deny entries are unaffected -- Bash is not a file-editing
tool and those rules match via the Bash matcher. `Read(<path>)` entries
are unaffected -- Read is its own matcher.

## Design

Delete these 12 entries from the `deny` array in
`claude/.claude/settings.base.json`:

```
Write(**/.env)
Write(**/.env.*)
Write(~/.ssh/*)
Write(~/.gnupg/*)
Write(~/.aws/credentials)
Write(~/.claude/.credentials.json)
Write(~/.kube/config)
Write(~/.docker/config.json)
Write(~/.netrc)
Write(~/.config/gh/hosts.yml)
NotebookEdit(**/.env)
NotebookEdit(**/.env.*)
```

Keep every `Read(<path>)`, `Edit(<path>)`, and `Bash(<glob>)` entry.

No replacement entries are needed: the corresponding `Edit(<path>)` rules
already exist and already deny Write + NotebookEdit for each path.

## Scope

- `claude/.claude/settings.overlay.json` -- checked, carries none of these
  entries. No change.
- Local/per-repo settings -- out of scope.

## Verification

1. Confirm each deleted path still has its `Edit(<path>)` sibling in the
   `deny` block (protection preserved).
2. `settings.base.json` remains valid JSON (`jq . <file>`).
3. Run `claude-sync` to regenerate `~/.claude/settings.json`; confirm the
   generated deny block dropped the 12 entries and stayed valid JSON.
4. Restart Claude Code (or start a fresh session) -- the 12 warnings no
   longer appear.

## Behavior change

None. `.env`, SSH keys, GPG keys, and the other secret paths remain
write-denied through their existing `Edit(...)` rules.
