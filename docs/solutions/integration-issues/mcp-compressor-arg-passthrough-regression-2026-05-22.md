---
title: "mcp-compressor 0.23.0 regressed required-argument passthrough on wrapped MCP servers"
date: 2026-05-22
category: integration-issues
module: claude
problem_type: integration_issue
component: tooling
symptoms:
  - "MCP error: 1 validation error for call[<tool>] / Missing required argument [type=missing_argument, input_value={}, input_type=dict]"
  - "Wrapped MCP tools rejecting every call carrying required arguments (jira_get_issue, jira_get_user_profile)"
  - "No-arg / all-optional tools on the same wrapped server still work (e.g. jira_search_fields), masking the regression"
root_cause: wrong_api
resolution_type: dependency_update
severity: high
related_components:
  - assistant
  - documentation
tags:
  - mcp-compressor
  - mcp-atlassian
  - mcp-dispatcher
  - uvx
  - version-pin
  - regression
  - claude-code
---

# mcp-compressor 0.23.0 regressed required-argument passthrough on wrapped MCP servers

## Problem

`mcp-compressor` 0.23.0 (PyPI 2026-05-21 21:50 UTC) regressed required-argument
passthrough in its default `compressed-tools` transform mode. Every dispatcher
call carrying required arguments reaches the wrapped backend with an empty
argument dict, and the backend rejects it. Tools with no required arguments
still work, which masks the breakage until the first call that needs a real
argument fails.

Because `~/.claude.json`'s entries invoke the compressor through `uvx
mcp-compressor` with no version pin, `uvx` resolves the latest release on
process start - so the four wrapped servers in this dotfiles config
(atlassian, qmd, sequential-thinking, slack) silently upgraded from
0.22.0 to 0.23.0 the moment the new release was cached locally on
2026-05-22, with no config change.

## Symptoms

- Pydantic validation error from the backend on every required-arg call:
  ```
  1 validation error for call[get_issue]
  issue_key
    Missing required argument [type=missing_argument, input_value={}, input_type=dict]
      For further information visit https://errors.pydantic.dev/2.13/v/missing_argument
  ```
- Reproduced against `mcp-atlassian` for both `jira_get_issue` and
  `jira_get_user_profile`.
- `jira_search_fields` (no required args) still returns data, which
  initially made the breakage look tool-specific rather than version-wide.
- Earlier session on the same day, same machine, same `~/.claude.json`
  entries verified live that `jira_get_issue` returned an issue payload.
  Between sessions, `uvx` flipped the resolved compressor to 0.23.0.

## What Didn't Work

- Trying different argument shapes on the dispatcher
  (`arguments={...}`, flat keys, `kwargs={...}`, `params={...}`). All four
  produced the same `input_value={}` error. The earlier dispatcher
  arg-shape hint added to CLAUDE.md (commit `01ea1db`) is still correct
  for the shape the compressor expects - the regression is in how 0.23.0
  forwards that payload to the backend, not in what the LLM passes in.
- Re-running `jira_get_user_profile` with the same `arguments` payload
  that worked in the earlier session. The argument was already in the
  shape the prior compressor accepted; the failure was below that layer.
- Inspecting the compressor's Python modules to localize the change. The
  dispatcher logic lives in the closed-source `_native.abi3.so` Rust core,
  so the diff between 0.22.0 and 0.23.0 was not directly readable.

## Solution

Pin `mcp-compressor` to the last known-good release (0.22.0) in the
`mcp-add` wrapper, then regenerate the four `~/.claude.json` entries so
they invoke the pinned form.

In `bin/.local/bin/mcp-add`, add an env-overridable version constant and
thread it into both `exec claude mcp add ...` branches:

```bash
set -euo pipefail

# Pin mcp-compressor to a known-good release. 0.23.0 (PyPI 2026-05-21)
# regressed required-argument passthrough in compressed-tools mode -
# the backend receives input_value={} and rejects every call carrying
# required arguments. See:
#   docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md
# Override per-invocation with MCP_COMPRESSOR_VERSION=<ver>.
MCP_COMPRESSOR_VERSION="${MCP_COMPRESSOR_VERSION:-0.22.0}"

# ... arg parsing unchanged ...

if [[ "$1" == "--" ]]; then
    shift
    exec claude mcp add --scope "$SCOPE" "$NAME" -- \
        uvx --from "mcp-compressor==$MCP_COMPRESSOR_VERSION" \
        mcp-compressor --server-name "$NAME" -- "$@"
else
    exec claude mcp add --scope "$SCOPE" "$NAME" -- \
        uvx --from "mcp-compressor==$MCP_COMPRESSOR_VERSION" \
        mcp-compressor --server-name "$NAME" "$1"
fi
```

`${X:-default}` works under `set -u`, so the unset case is safe.

Then, because `~/.claude.json` is gitignored and Claude-managed, the
existing entries do not pick up the pin automatically. Regenerate each
wrapped entry and restart Claude:

```sh
for s in atlassian qmd sequential-thinking slack; do
  claude mcp remove --scope user "$s"
done

mcp-add atlassian              -- uvx mcp-atlassian
mcp-add qmd                    -- qmd mcp
mcp-add sequential-thinking    -- npx -y @modelcontextprotocol/server-sequential-thinking
mcp-add slack                  -- npx -y @modelcontextprotocol/server-slack
```

After restart, `jq '.mcpServers.atlassian.args | join(" ")' ~/.claude.json`
must include `--from mcp-compressor==0.22.0`, and a fresh Claude session
must be able to call `jira_get_issue(arguments={"issue_key":"INFRA-362"})`
and receive a real issue payload.

## Why This Works

`uvx --from <package>==<version> <command>` forces uv to resolve and run
exactly the pinned distribution rather than the latest. With 0.22.0
restored, the dispatcher's required-arg passthrough behaves as the
backend expects (verified working in the earlier session on the same
day). The env-overridable constant (`MCP_COMPRESSOR_VERSION`) lets a
future session test a newer release without editing the wrapper:

```sh
MCP_COMPRESSOR_VERSION=0.24.0 mcp-add <name> -- <cmd>
```

When upstream fixes the regression, bump the default in `mcp-add` and
re-run the regeneration block above.

The fix lives in the wrapper rather than the entries themselves because
`~/.claude.json` cannot be stowed (Claude rewrites it). The wrapper is
the only reproducible carrier for a per-host pin across the four
wrapped servers.

## Prevention

- Pin every `uvx`-resolved tool with `--from <package>==<version>` when
  the tool is used in long-running, latency-sensitive, or
  contract-sensitive contexts (MCP wrappers, daemons, hook scripts).
  `uvx` defaults to "latest" and silently picks up regressions between
  sessions.
- When wrapping a third-party MCP server, write a smoke test that
  exercises at least one tool with a required argument. No-arg tools
  succeed even when arg passthrough is broken, so a smoke test that
  only calls a no-arg tool will not catch this class of regression.
- When a tool that "worked yesterday" suddenly fails with arg-related
  errors and no local change explains it, check `uvx`'s resolved
  version first (`uvx <tool> --version`) before exploring backend or
  client-side hypotheses.

## Related Issues

- `docs/solutions/developer-experience/mcp-compressor-dispatcher-hint-2026-05-22.md` -
  earlier learning from the same day about the dispatcher's empty
  advertised `inputSchema`. Still accurate - the arg-shape hint there
  describes what the compressor expects from the LLM, while this doc
  covers a separate regression in how 0.23.0 forwards that payload to
  the backend.
- `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md` - the
  spec for this fix.
- `docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md` - the
  implementation plan.
