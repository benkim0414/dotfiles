# Task 2 brief: safe Codex sync and activation preparation

Requirements: Task 2 and global constraints of docs/superpowers/plans/2026-09-30-codex-official-setup.md. Task 1 changes config.base.toml, AGENTS.md, retires hooks and hook-specific tests. Do not rewrite its decisions.

## Facts and implementation boundaries

- Generated config.toml is ignored, config.base.toml is tracked.
- ~/.codex is a symlink to the primary dotfiles codex/.codex directory. live_config and generated_config can be the same physical regular file. Handle this case without replacing it with a self-referential symlink or rejecting it after mutation.
- The old sync overwrites live settings, requires the removed hooks, and removes only its legacy managed hooks.json symlink. Preserve semantic unrelated TOML settings, model selections, trusted projects, official plugin enabled state, and other runtime config. Do not print their contents.
- No tomlkit, tomli_w, or toml package is installed. Use existing dependencies and Python stdlib if needed; do not install software.
- Replaced decisions (permissions/reviewer, third-party plugin/marketplace/context-mode removals, custom hook retirement, skill disables) must beat stale live values. Do not re-enable rejected integrations via merge.
- Preserve unmanaged files/symlinks; preflight failures must leave original live and generated files unchanged. Known managed hook links may be retired, but never delete arbitrary user hooks or shared assets. Report an incompatible unmanaged hook source and stop before activation instead of silently ignoring it.
- Non-primary worktree generation must not activate or modify live user files without explicit CODEX_HOME targeting or CODEX_SYNC_LIVE opt-in. Reading existing live TOML for preservation is permitted without touching credentials. Test HOME path mapping, symlink paths, regular-file same-target, unrelated destination refusal, malformed TOML, repeat execution, and generated configuration semantics.
- Tests must exercise real generation/merging and rollback relevant failure boundaries rather than mirror private helpers.

## Deliverables

Update codex-sync and its integration tests. Add a small supporting helper only if needed for correct TOML merging. Add docs/guides/codex-official-setup.md with exact reviewed-branch activation instructions and rollback, including backups of config/AGENTS/base/sync enablement state without credentials or shared skills, fresh-session checks, and restrictions imposed by ~/.codex pointing into main. Do not merge, activate, push, delete worktrees/branches, or change main.

Record commands, outcomes, implementation choices, and limitations in docs/research/codex-official-setup-task-2-report.md. Commit explicit relevant paths only after inspecting diff/cached diff and checks. No subagents; controller supplies reviews.
