# Drop mcp-compressor wrapper for all wrapped MCP servers

Date: 2026-05-22
Branch: worktree-atlassian-mcp-drop-compressor
Supersedes: `2026-05-22-atlassian-mcp-fix-design.md` (the 0.22.0 pin hypothesis was wrong)

## Problem

The `atlassian` MCP server, wrapped by `uvx mcp-compressor` in
`compressed-tools` transform mode, rejects every Claude Code call that
carries required arguments. The backend (`mcp-atlassian`) sees an empty
argument dict and emits:

```
1 validation error for call[get_user_profile]
user_identifier
  Missing required argument [type=missing_argument, input_value={}, input_type=dict]
```

Reproduced on 2026-05-22 against `jira_get_user_profile`,
`jira_get_issue`, and `jira_search` via the Claude `Atlassian` MCP tool,
with every documented argument shape (inline `arguments` object, flat
keys at dispatcher level, `input`/`tool_input`/`kwargs`/`params`
wrappers, JSON-string `arguments`). All produce the same `input_value={}`
error.

The earlier same-day fix (commit `477af34`) pinned `mcp-compressor` to
`0.22.0` on the theory that `0.23.0` regressed the dispatcher. The pin
landed and was verified to be running (`uvx --from
mcp-compressor==0.22.0 mcp-compressor`), but required-arg calls still
fail.

## Root cause (high confidence)

The compressor's `compressed-tools` mode advertises both dispatcher
tools (`<server>_get_tool_schema`, `<server>_invoke_tool`) with an empty
`inputSchema`:

```json
{ "type": "object", "properties": {} }
```

A raw stdio bisect of mcp-compressor versions `0.10.0`, `0.13.0`,
`0.17.0`, `0.20.0`, `0.21.0`–`0.21.3`, `0.22.0`, `0.23.0` revealed that
the correct magic key for `invoke_tool` is **`tool_input`**, not
`arguments` as the existing CLAUDE.md note claims. Raw stdio call with
`tool_input` succeeds on `0.22.0`:

```json
{"name":"atlassian_invoke_tool",
 "arguments":{"tool_name":"jira_get_user_profile",
              "tool_input":{"user_identifier":"x@example.com"}}}
```

The backend receives the argument and returns a real error
(`Could not resolve email …`).

Through Claude Code, the same call fails. Claude's MCP client validates
`arguments` against the advertised schema. With `properties: {}`, every
declared key in the call is treated as unknown and stripped before the
request reaches the compressor. `get_tool_schema(tool_name=…)` happens
to work only because that path is implemented inside the compressor's
own frontend (it never forwards args to the backend); `invoke_tool`
must forward args and cannot, because Claude removed them.

This is not a regression. The bug is structural in the
`compressed-tools` transform mode and has existed across every release
available on PyPI. The hint subsection added to CLAUDE.md in commit
`01ea1db` is wrong (`arguments` is not the magic key, and even
`tool_input` is stripped by Claude). The 0.22.0 fix in `477af34` is
wrong (the regression hypothesis was incorrect; the bug predates the
pin).

## Goals

1. Restore usability of the four wrapped MCP servers (`atlassian`,
   `qmd`, `sequential-thinking`, `slack`) by removing the compressor
   wrapper.
2. Remove dead code and documentation that promote the broken pattern
   (the `mcp-add` helper, the `MCP servers wrapped by mcp-compressor`
   CLAUDE.md section, the stale memory note).
3. Retract the prior fix and hint specs in place so future readers see
   the corrected story without losing the audit trail.
4. Capture the investigation method (raw stdio bisect, `tool_input`
   discovery, schema-strip mechanism) as a learning so the next
   compressor or schemaless-dispatcher problem solves faster.

## Non-goals

- Filing an upstream bug at `atlassian-labs/mcp-compressor`. Deferred.
- Switching `atlassian` to the `claude.ai`-hosted Atlassian MCP. Auth
  surface and tool naming differ; out of scope.
- Adding any custom proxy or schema-injecting wrapper. YAGNI.
- Re-evaluating whether token-compression is worth pursuing through a
  different mechanism (compressor's `cli` or `just-bash` modes, a
  custom shim). Out of scope.

## Design

### Part 1 — Regenerate `~/.claude.json` for the four servers

`~/.claude.json` is managed by Claude Code, gitignored, and not stowed.
The fix lives in this file. Operator runs the regeneration once after
merge, then restarts Claude.

```sh
# Remove existing wrapped entries
for s in atlassian qmd sequential-thinking slack; do
  claude mcp remove --scope user "$s"
done

# Re-add as raw backends (no compressor)
claude mcp add --scope user atlassian            -- uvx mcp-atlassian
claude mcp add --scope user qmd                  -- qmd mcp
claude mcp add --scope user sequential-thinking  -- npx -y @modelcontextprotocol/server-sequential-thinking
claude mcp add --scope user slack                -- npx -y @modelcontextprotocol/server-slack
```

Trade-off acknowledged: raw `mcp-atlassian` advertises ~30 tools with
full schemas, increasing tools/list payload per session relative to the
compressor's two dispatcher tools. Required-arg invocations work, which
is the goal.

### Part 2 — Delete `bin/.local/bin/mcp-add`

The helper exists to produce `uvx mcp-compressor` invocations. With no
servers wrapped, no use case remains. Remove:

- `bin/.local/bin/mcp-add`
- Any `mcp-add`-related tests if present (search step in plan)

After removal, `stow -t ~ -R bin` reconciles the symlink in
`~/.local/bin`.

### Part 3 — Prune CLAUDE.md `MCP servers wrapped by mcp-compressor`

Replace the entire section (including the `### Version pin` and the
dispatcher-hint subsection) with a shorter note explaining that the
four servers run raw, that a prior wrapping attempt was abandoned, and
linking to this spec. Keeps the index entry findable without preserving
the broken guidance.

### Part 4 — Rewrite memory note in place

`reference_atlassian_dispatcher_bug.md` currently attributes the bug to
a 0.23.0 regression and prescribes the wrong workaround (`arguments`
key). Rewrite the body to capture the true root cause (empty schema +
Claude strict validator) and the resolution (compressor dropped for
these servers). Keep the slug so the existing `MEMORY.md` index entry
still resolves.

### Part 5 — Retract prior specs/plans in place

Add a "RETRACTED" header section at the top of:

- `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md`
- `docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md`
- `docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md`
- `docs/solutions/developer-experience/mcp-compressor-dispatcher-hint-2026-05-22.md`
- `docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md`

Each header points to this spec and the new learning doc. Body of the
old docs is preserved so the historical reasoning stays auditable.
For solution docs with YAML frontmatter, the header is inserted after
the closing `---` so the frontmatter parser still resolves cleanly.

### Part 6 — Write the learning doc

`docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`
captures:

- Symptom: pydantic `input_value={}` on required-arg backend calls.
- Mechanism: compressor `compressed-tools` mode advertises empty
  `inputSchema`; Claude Code MCP client strips non-declared keys
  before forwarding `arguments`.
- Investigation method: raw stdio bisect (spawn
  `uvx --from mcp-compressor==X.Y.Z mcp-compressor … -- <backend>`,
  send `initialize` + `tools/call`, observe payload). Six arg-shape
  variants per version; `tool_input` was the magic key that worked in
  raw stdio.
- Resolution: drop compressor for affected servers. Pin and
  arg-shape-hint hypotheses retracted.
- Generalizable lesson: when an MCP dispatcher advertises `properties:
  {}`, treat Claude Code as incompatible with that server for tools
  with required arguments. Verify dispatcher shape before adopting a
  compression wrapper.

## Files touched

- `bin/.local/bin/mcp-add` — delete.
- `claude/.claude/CLAUDE.md` — rewrite `MCP servers wrapped by
  mcp-compressor` section.
- `docs/superpowers/specs/2026-05-22-atlassian-mcp-drop-compressor-design.md`
  — this spec.
- `docs/superpowers/plans/2026-05-22-atlassian-mcp-drop-compressor.md`
  — implementation plan (writing-plans output).
- `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md` —
  prepend RETRACTED header.
- `docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md` — prepend
  RETRACTED header.
- `docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md`
  — prepend RETRACTED header.
- `docs/solutions/developer-experience/mcp-compressor-dispatcher-hint-2026-05-22.md`
  — prepend RETRACTED header.
- `docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md`
  — prepend RETRACTED header (after frontmatter).
- `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`
  — new learning doc.
- (External, not in repo) `~/.claude/projects/-Users-ben-workspace-dotfiles/memory/reference_atlassian_dispatcher_bug.md`
  — rewrite body.

## Verification

After running the regeneration procedure and restarting Claude:

1. `mcp__atlassian__jira_get_issue(issue_key="INFRA-362")` returns the
   issue payload. (Pre-fix: `input_value={}` pydantic error.)
2. `mcp__atlassian__jira_get_user_profile(user_identifier="ben.kim@greenenergytrading.com.au")`
   returns the user profile.
3. `mcp__atlassian__*_invoke_tool` and `mcp__atlassian__*_get_tool_schema`
   no longer appear in the available MCP tool list. Direct backend tools
   (`mcp__atlassian__jira_search`, etc.) appear instead.
4. Same shape holds for `qmd`, `sequential-thinking`, `slack`:
   dispatcher tools gone, direct tools appear.
5. `which mcp-add` returns nothing. `bin/.local/bin/mcp-add` symlink is
   gone after `stow -t ~ -R bin`.
6. `jq '.mcpServers.atlassian.args' ~/.claude.json` returns
   `["mcp-atlassian"]`, not the `--from mcp-compressor==…` form.

## Rollback

Full: revert this branch, restore `bin/.local/bin/mcp-add` (now
including the 0.22.0 pin from `477af34`), run the regeneration
procedure with the restored helper. Restart Claude. Servers return to
compressor-wrapped state — still broken for required-arg calls, matches
the broken baseline that existed before this work.

Partial (low-risk): revert only `~/.claude.json` via manual `claude mcp
remove` + `mcp-add` for each server. Repo changes (script deletion,
CLAUDE.md prune, retraction headers, learning doc) can stand without
the runtime revert.

## Open questions

- The `qmd`, `sequential-thinking`, `slack` servers were tested only on
  no-required-arg calls during this investigation. Required-arg calls
  through Claude on those servers are presumed broken by the same
  empty-schema mechanism, but not empirically confirmed. The drop is
  applied uniformly because (a) the mechanism is structural, not
  per-server, and (b) the cost of running raw backends is minor
  compared to leaving silent failures behind required-arg tools.
- The token-compression benefit lost by going raw is non-trivial
  (especially for `atlassian` with ~30 tools). A future revision could
  reintroduce compression through a different mechanism (custom
  schema-aware proxy, `cli` transform mode, claude.ai-hosted servers)
  once the workflow stabilizes.
