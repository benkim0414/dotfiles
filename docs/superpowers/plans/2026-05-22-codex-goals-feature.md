# Codex Goals Feature Implementation Plan

## Goal

Enable Codex's native `/goal` feature in the dotfiles-managed Codex configuration and apply it through the existing sync workflow.

## References

- Spec: `docs/superpowers/specs/2026-05-22-codex-goals-feature-design.md`
- Source config: `codex/.codex/config.base.toml`
- Generated config: `codex/.codex/config.toml`
- Sync script: `bin/.local/bin/codex-sync`
- Sync tests: `codex/.codex/tests/test-codex-sync-hooks.sh`

## Task 1: Add a Failing Config Assertion

Update `codex/.codex/tests/test-codex-sync-hooks.sh` so it asserts that generated Codex config contains the goals feature flag after sync.

Add an assertion near the existing generated-config checks:

```sh
assert_file_contains "$generated_config" "goals = true"
```

Run the test and confirm it fails before changing the config:

```sh
codex/.codex/tests/test-codex-sync-hooks.sh
```

Expected failure: the generated config does not contain `goals = true`.

## Task 2: Enable the Feature in the Source Config

Edit `codex/.codex/config.base.toml`.

Under the existing `[features]` table, add:

```toml
# Enable durable /goal workflows for long-running tasks with clear stopping conditions.
goals = true
```

Keep the existing `[features]` table location. Do not add a second `[features]` table.

## Task 3: Regenerate and Apply Codex Config

Run the existing sync script from the worktree:

```sh
bin/.local/bin/codex-sync
```

This should copy `config.base.toml` to `codex/.codex/config.toml` and, because this worktree is not the primary dotfiles checkout unless `CODEX_HOME` or `CODEX_SYNC_LIVE=1` is set, may stop after generating the worktree-local config. If live wiring is skipped, rerun from the primary checkout after the branch is merged or explicitly run with the intended live wiring environment.

Because the approved design asks to apply it live now, run the sync against the primary checkout after the config change is available there, or run with `CODEX_HOME` pointing at the intended live Codex home if applying from this worktree.

## Task 4: Verify

Run:

```sh
codex/.codex/tests/test-codex-sync-hooks.sh
```

Inspect both source and generated config:

```sh
rg -n "goals = true|\\[features\\]" codex/.codex/config.base.toml codex/.codex/config.toml
```

If live config was updated in this session, inspect it too:

```sh
rg -n "goals = true|\\[features\\]" "$CODEX_HOME/config.toml"
```

If `CODEX_HOME` is unset, use `$HOME/.codex/config.toml`.

## Task 5: Commit Implementation

Commit the implementation separately from the spec commit:

```sh
git add codex/.codex/config.base.toml codex/.codex/config.toml codex/.codex/tests/test-codex-sync-hooks.sh docs/superpowers/plans/2026-05-22-codex-goals-feature.md
git commit -m "feat(codex): enable goals feature"
```

## Non-Goals

- Do not create or resume a Codex goal.
- Do not change approval, sandbox, hooks, MCP, plugin, or AGENTS behavior.
- Do not replace the existing `codex-sync` workflow.
