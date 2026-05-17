# Codex Hooks Single Source Design

## Context

Codex currently has hook configuration split across two live sources:

- `codex/.codex/config.base.toml`, which generates `codex/.codex/config.toml`
- `codex/.codex/hooks.json`, which is symlinked into `~/.codex/hooks.json`

The visible failure is:

```text
PreToolUse hook (failed) error: hook exited with code 127
```

Investigation found two concrete causes:

- `hooks.json` invokes `context-mode hook codex pretooluse` as a bare command. It works in the interactive shell, but fails with exit `127` under a restricted hook-style `PATH` because `context-mode` is installed through mise.
- `config.base.toml` invokes `bash "$HOME/.codex/hooks/atomic-commits.sh"`, but `~/.codex/hooks/atomic-commits.sh` is not currently wired. The tracked script exists at `codex/.codex/hooks/atomic-commits.sh`.

The desired outcome is a single durable source of truth for Codex hook configuration, with live wiring that stops the current hook failures immediately.

## Goals

- Move Codex hook registrations from `hooks.json` into `config.base.toml`.
- Keep `codex/.codex/config.toml` generated from `config.base.toml` through `codex-sync`.
- Retire live `~/.codex/hooks.json` wiring after the TOML migration.
- Make hook commands work in Codex's non-interactive hook environment.
- Preserve the existing atomic commit guard behavior.
- Verify the fix with restricted `PATH` reproductions, not only an interactive shell.

## Non-Goals

- Redesign the atomic commit hook's policy.
- Change context-mode behavior.
- Change unrelated Codex plugin or marketplace configuration.
- Rework the full dotfiles stow layout.

## Architecture

`codex/.codex/config.base.toml` becomes the only checked-in hook registration source. It should contain the existing atomic commit `PreToolUse` hook plus context-mode hooks for the events currently registered in `hooks.json`:

- `PreToolUse`
- `PostToolUse`
- `SessionStart`
- `PreCompact`
- `UserPromptSubmit`
- `Stop`

`bin/.local/bin/codex-sync` continues to generate `codex/.codex/config.toml` from `config.base.toml`. If live wiring needs more than copying the generated config, `codex-sync` may also perform idempotent setup for `~/.codex` paths.

`codex/.codex/hooks.json` should be removed from active use. After migration, `~/.codex/hooks.json` should be absent or disconnected so Codex cannot read a second hook source that conflicts with `config.toml`.

## Hook Command Resolution

Hook commands must not rely on the user's interactive shell initialization. The context-mode hook command should use a path that resolves when Codex runs hooks with a restricted `PATH`.

The preferred shape is a stable user-level wrapper path, such as:

```text
$HOME/.local/bin/context-mode
```

That wrapper can resolve the mise-installed `context-mode` executable. If a wrapper already exists and works under a restricted `PATH`, reuse it. If not, add one as part of the implementation.

The atomic commit hook should either:

- call the tracked script path directly, or
- keep the `$HOME/.codex/hooks/atomic-commits.sh` command and make `codex-sync` wire that symlink idempotently.

The second option keeps the live command short and local to `~/.codex`, but it requires sync-time wiring. The implementation plan should choose the simpler option after checking existing dotfiles conventions.

## Live Wiring

The migration should make live state match the new source of truth:

- `~/.codex/config.toml` points to `~/workspace/dotfiles/codex/.codex/config.toml`.
- `~/.codex/hooks/atomic-commits.sh` exists if `config.toml` references that path.
- `~/.codex/hooks.json` is removed or disconnected after the TOML migration.
- Any context-mode wrapper referenced by hooks exists and exits successfully.

The wiring must be idempotent so it is safe to rerun after future config changes.

## Error Handling

If a required executable or tracked script is missing, the sync or wiring step should fail with a clear message that names the missing path. It should not silently create hook registrations that will later fail with exit `127`.

If `~/.codex/hooks.json` is present and is not the expected old symlink, the migration should avoid overwriting it destructively. It should report the path and require manual handling.

## Testing

Verification should cover both isolated commands and live config state:

- Run the context-mode hook command under a restricted `PATH` and confirm exit `0`.
- Run the atomic commit hook with a harmless shell command payload and confirm exit `0`.
- Confirm `codex-sync` regenerates `codex/.codex/config.toml` with all migrated hooks.
- Confirm `~/.codex/hooks.json` is no longer an active live hook source.
- Run the existing atomic commit hook test if it remains applicable.

The restricted `PATH` checks are required because they reproduced the failure more accurately than the interactive shell.
