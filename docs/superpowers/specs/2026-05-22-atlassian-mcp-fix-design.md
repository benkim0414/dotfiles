# Atlassian MCP fix - pin mcp-compressor to 0.22.0

Date: 2026-05-22
Branch: worktree-atlassian-mcp-fix

## Problem

The `atlassian` MCP server, wrapped by `uvx mcp-compressor` (transform mode
`compressed-tools`), rejects all dispatcher calls that carry required
arguments. The backend (`mcp-atlassian`) receives an empty argument dict
and emits a pydantic validation error:

```
1 validation error for call[get_user_profile]
user_identifier
  Missing required argument [type=missing_argument, input_value={}, input_type=dict]
```

Reproduced in this session on both `jira_get_user_profile` and
`jira_get_issue`, with `arguments` supplied four ways: as an inline object,
as flat keys, under `kwargs`, under `params`. All four produce the same
empty `input_value={}` error. Tools with no required arguments
(`jira_search_fields` called with `arguments={}`) still work, which
confirms the dispatcher itself reaches the backend - the required-arg
payload is being dropped between the dispatcher and the backend invocation.

The earlier session today, recorded in
`docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md`,
verified live that
`mcp__atlassian__atlassian_invoke_tool(tool_name="jira_get_issue", arguments={"issue_key":"INFRA-362"})`
returned the issue payload. The same call now fails. The breakage occurred
between that session and this one - same date, same machine, same
`~/.claude.json` entries.

## Root cause (high confidence)

mcp-compressor 0.23.0 regressed required-arg passthrough in
`compressed-tools` mode.

- PyPI: `mcp-compressor==0.23.0` uploaded 2026-05-21 21:50 UTC.
- Local uv cache for 0.23.0 created 2026-05-22 09:41 (today, before this
  Claude session started). uvx with no version pin resolves to the latest
  available, so the running compressor flipped from 0.22.0 to 0.23.0 some
  time between the prior session and this one without any config change.
- Both `_native.abi3.so` (Rust core) and every Python module differ
  between 0.22.0 and 0.23.0. The dispatcher logic lives in the Rust core,
  which is closed-source - no inline diff possible.
- The same `mcp-add`-generated `~/.claude.json` entries that worked under
  0.22.0 fail under 0.23.0. The only changed dependency is the compressor
  binary that `uvx` resolves.

A workaround that does not require the compressor (raw `mcp-atlassian` MCP
server, claude.ai-hosted Atlassian OAuth MCP, swap to `cli` or `just-bash`
transform mode) was explicitly rejected during brainstorming. The chosen
path is to pin the compressor to the last known-good version, regenerate
the wrapped entries, and document the pin in CLAUDE.md.

Filing an upstream issue at `atlassian-labs/mcp-compressor` was explicitly
deferred. The hint-design predecessor already deferred upstream filing
once today; this spec inherits that decision. Revisit if the pin needs to
stay for more than a release cycle.

## Goals

1. Restore atlassian MCP usability against the existing self-hosted
   `mcp-atlassian` backend without changing auth, scope, or tool surface.
2. Make the pin reproducible across machines so the dotfiles repo carries
   the fix, not just the current laptop's `~/.claude.json`.
3. Document the pin (which version, why, how to unpin) where future
   sessions and the next operator will find it.

## Non-goals

- Filing an upstream bug at `atlassian-labs/mcp-compressor`. Deferred per
  brainstorming decision.
- Bisecting the Rust core to identify the exact commit that broke
  required-arg passthrough. Out of reach without source.
- Switching transform mode (`cli`, `just-bash`) or dropping the compressor
  wrapper entirely. Loses the 70-97% token-compression benefit that the
  `mcp-add`-based setup exists for.
- Touching the in-session installed `mcp-compressor` binary. The fix
  surfaces only after Claude is restarted with the regenerated entries.

## Design

### Part 1 - pin in `mcp-add`

`bin/.local/bin/mcp-add` currently invokes
`uvx mcp-compressor --server-name "$NAME" ...`. With no version pin, uvx
resolves the latest. Change it to read a constant (env-overridable) and
pass `--from "mcp-compressor==$MCP_COMPRESSOR_VERSION"`:

```bash
MCP_COMPRESSOR_VERSION="${MCP_COMPRESSOR_VERSION:-0.22.0}"

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

The env override lets a future session test a newer compressor release
without editing the script - useful when upstream fixes the regression.
Default stays 0.22.0 until the pin is bumped explicitly.

### Part 2 - regenerate the four wrapped `~/.claude.json` entries

`~/.claude.json` is managed by Claude Code, gitignored, and not stowed -
the fix to `mcp-add` has no effect on entries that already exist. The
four wrapped servers (`atlassian`, `qmd`, `sequential-thinking`, `slack`)
all need their entries rewritten so the pinned `uvx --from ...` form
takes effect.

Procedure (run after merge, requires `claude` CLI):

```sh
# Remove existing entries
for s in atlassian qmd sequential-thinking slack; do
  claude mcp remove --scope user "$s"
done

# Re-add via the now-pinned mcp-add (commands match the originals in
# ~/.claude.json that mcp-add produced - the only change is the version
# pin injected by mcp-add)
mcp-add atlassian              -- uvx mcp-atlassian
mcp-add qmd                    -- qmd mcp
mcp-add sequential-thinking    -- npx -y @modelcontextprotocol/server-sequential-thinking
mcp-add slack                  -- npx -y @modelcontextprotocol/server-slack
```

Then restart Claude Code so the new `uvx --from ...` invocation replaces
the running compressor process for each server.

### Part 3 - document the pin in CLAUDE.md

Append a "Version pin" subsection to the existing
`## MCP servers wrapped by mcp-compressor` section in
`claude/.claude/CLAUDE.md`:

```markdown
### Version pin

`mcp-add` pins `mcp-compressor` to 0.22.0 via
`uvx --from mcp-compressor==0.22.0`. 0.23.0 (PyPI 2026-05-21) regressed
required-arg passthrough in `compressed-tools` mode - the backend
receives `input_value={}` and rejects every call with required arguments.
Reproduced against `mcp-atlassian` (jira_get_issue, jira_get_user_profile)
on 2026-05-22.

To test a newer release without editing `mcp-add`:

    MCP_COMPRESSOR_VERSION=0.24.0 mcp-add <name> -- <cmd>

To bump the default after upstream fixes it, change the constant in
`bin/.local/bin/mcp-add` and re-run the regeneration procedure in
`docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md`.
```

The hint subsection already in CLAUDE.md (added today by commit `01ea1db`)
stays as-is - the empty advertised inputSchema is a separate concern from
the 0.23.0 arg-passthrough regression.

## Files touched

- `bin/.local/bin/mcp-add` - inject version pin, env-overridable.
- `claude/.claude/CLAUDE.md` - new "Version pin" subsection.
- `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md` - this
  spec.
- `docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md` - implementation
  plan produced by writing-plans after spec approval.
- `docs/solutions/developer-experience/atlassian-mcp-fix-2026-05-22.md` -
  solution doc produced by ce-compound after implementation.

## Verification

After merging the branch and running the regeneration procedure, restart
Claude and confirm:

1. `mcp__atlassian__atlassian_invoke_tool(tool_name="jira_get_issue", arguments={"issue_key":"INFRA-362"})`
   returns an issue payload (was: pydantic error, now: success).
2. `mcp__atlassian__atlassian_invoke_tool(tool_name="jira_get_user_profile", arguments={"user_identifier":"ben.kim@greenenergytrading.com.au"})`
   returns a user profile (was: pydantic error, now: success).
3. `mcp__slack__slack_invoke_tool(tool_name="slack_list_channels", arguments={"limit":3})`
   still works (no regression on the previously-working server).
4. `uvx --from mcp-compressor==0.22.0 mcp-compressor --version` prints
   `mcp-compressor 0.22.0` - confirms uvx is picking the pinned version.
5. `jq '.mcpServers.atlassian.args | join(" ")' ~/.claude.json` contains
   `--from mcp-compressor==0.22.0`.

The pre-fix state for items 1 and 2 is the pydantic validation error
captured in this spec's "Problem" section.

## Rollback

Revert this branch and run the regeneration procedure (`claude mcp remove`
+ `mcp-add` for each of the four servers) so `~/.claude.json` no longer
carries the `--from mcp-compressor==X.Y.Z` flag. The unpinned `mcp-add`
will go back to resolving the latest mcp-compressor at process start.

## Open questions

- Does the 0.23.0 regression affect the other three wrapped servers
  (qmd, sequential-thinking, slack) when required arguments are passed,
  or only atlassian? The pin is applied uniformly because `mcp-add` is
  shared, so this does not block the fix - but if other servers turn out
  to be unaffected, a future revision could limit the pin to atlassian.
  Slack `slack_list_channels(limit:5)` worked this session, but `limit`
  is optional; required-arg slack tools were not tested.

## Out-of-spec follow-ups

- Memory entry `reference_atlassian_dispatcher_bug.md` (saved earlier in
  this conversation) currently attributes the bug to the compressor
  dispatcher in general terms. Update it to point at the 0.23.0 regression
  specifically and to reference this spec, after the spec lands on `main`.
