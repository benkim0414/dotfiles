# Task 2: safe sync and activation preparation

The launcher delegates to a Python 3.11+ stdlib helper. It parses live TOML, overlays unrelated values on the base, then reapplies explicitly owned migration decisions. Existing models, reasoning effort, trusted projects, other MCP servers, and official plugin enabled states survive. Semantic TOML equality is checked after serialization before an atomic generated-file replacement; comments and original formatting are not preserved. Skill aliases are compared by resolved paths so stale enabled aliases cannot override the retired entries.

All destination, hook-source, parsing, and serialization refusal checks precede file mutation. Linked checkout generation reads live configuration but does not activate it without explicit CODEX_HOME or CODEX_SYNC_LIVE. The live/generated same-physical-file case is supported without creating a self-referential symlink. Only recognized legacy hook links are retired; unmanaged hook sources cause a diagnostic and refusal. Diagnostics omit config contents.

## Verification

- `bash -n bin/.local/bin/codex-sync`: passed.
- `python3 codex/.codex/tests/test-codex-sync.py`: seven integration tests passed. These invoke the real launcher with isolated HOME/checkout files and cover semantic preservation, repeat generation/activation, HOME mapping, regular same-target and symlink layouts, managed hook retirement, unmanaged hook/destination refusal, malformed TOML without content disclosure, no mutation on refusal, explicit opt-in, and skill alias exclusion.
- `python3 /tmp/codex-task2-probe.py`, launching bounded `codex app-server --strict-config --stdio` against `/tmp/codex-artifact-validation`: passed, exit 0. The fixture contains copied official manifest/skill metadata, no credentials or live cache symlinks. The generated configuration preserves actual live `gpt-6.1-sol` and `low` settings.

The probe issues initialize, skills/list, config/read, and hooks/list RPCs without model calls. Observed result: 40 skills, six enabled official artifact skills, five enabled system skills, 29 disabled shared skills, user/on-request/workspace-write, hooks false, and an empty hooks list with no warnings or errors. Task 1 separately proved legacy ELI5 exclusion using the unchanged actual skill and an enabled control; that absent legacy skill is not counted in this fixture's 40 entries.

## Limits and activation

Activation and rollback steps are in `docs/guides/codex-official-setup.md`. No primary checkout, live config, credentials, shared skills, cache, or installation was modified. No merge or push was performed. Primary integration and live activation require direct user approval. The private backup stays in an ignored workspace directory. This session cannot verify refresh of already injected host tools/instructions; a fresh interactive session remains an activation check.

Filesystem failures after the atomic generated-file replacement (for example, permissions changing before link creation or hook unlinking) are not a multi-file transaction. Preflight failures are covered by integration tests; operational failure after replacement requires the documented backup restoration. The helper requires Python 3.11's tomllib, already installed here. The npm Codex launcher needs process-group cleanup after RPC completion; the bounded probe uses a new process session and targeted group termination.
