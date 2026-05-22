# mcp-compressor dispatcher hint

Date: 2026-05-22
Status: Draft, awaiting user review
Worktree branch: `worktree-mcp-compressor-dispatcher-hint`

## Problem

Four MCP servers in `~/.claude.json` (slack, atlassian, qmd,
sequential-thinking) are wrapped by `uvx mcp-compressor ... --
<backend>`. The compressor's default `compressed-tools` mode replaces
each backend's tool surface with two dispatcher tools:

- `<server>_get_tool_schema`
- `<server>_invoke_tool`

Each dispatcher requires a `tool_name` argument server-side, but the
`inputSchema` advertised over MCP is `{"type":"object","properties":{}}`
- it does not declare `tool_name` (or `arguments`). When a fresh
Claude session sees the tool, the schema implies no params; the LLM
calls it with `{}`, the compressor returns
`MCP error -32602: missing tool_name`, and the user perceives the MCP
as "rejecting args".

Past Claude Code session
`-Users-ben-workspace-expo-onsite-app/515e29f7-b229-4c9f-87e4-e0a1800601a7.jsonl`
(2026-05-22 02:17-03:01) shows the prior model burning ~20 attempts
cycling through arg shapes (`name`, `tool_name`+`arguments` as JSON
string, `tool_name`+inline keys, `tool_name`+`arguments_json`,
`tool_name`+`params`, `tool_name`+`input`, `tool_name`+`kwargs`, ...)
before converging on a shape that worked. Some sessions converge,
others give up.

Reproduced live in this conversation:

- `mcp__slack__slack_get_tool_schema()` -> `-32602 missing tool_name`.
- `mcp__slack__slack_get_tool_schema(tool_name="slack_list_channels")`
  -> returns full schema for `slack_list_channels`.
- `mcp__slack__slack_invoke_tool(tool_name="slack_list_channels", arguments={"limit": 3})`
  -> returns channel list. The dispatcher works once shape is known.

Bug class: upstream `mcp-compressor` (atlassian-labs/mcp-compressor)
advertises an incomplete `inputSchema` for its dispatcher tools.
Confirmed against versions 0.18.1, 0.20.0, 0.22.0, 0.23.0 and all four
compression levels (`low`, `medium`, `high`, `max`). Not a regression -
a design flaw of `compressed-tools` mode against schema-aware clients
(Anthropic Claude Code, OpenAI tool-use, etc.).

## Constraints

- Compression is worth keeping; raw tools/list payloads for the four
  servers are sizeable and the wrap was added 2026-04-21 to control
  context cost.
- Fix must survive context compaction (the hint cannot live only in
  ephemeral session state).
- Must work for fresh sessions on the first dispatcher call - the
  whole point is to remove the trial-and-error phase.
- No backend-credential changes required (env propagation already
  works; verified in current session).

## Design

Two-part fix.

### Part 1 - session-resident hint

Add a short, authoritative section to `~/.claude/CLAUDE.md` (stowed
from `dotfiles/claude/.claude/CLAUDE.md`) that teaches the dispatcher
arg shape. CLAUDE.md is always-on context, never compacted, so the
hint reaches every session at message zero - eliminating the fumble.

Proposed section, inserted after the existing "Semantic Search (qmd)"
block:

```markdown
## MCP servers wrapped by mcp-compressor

Four servers in `~/.claude.json` (atlassian, qmd, sequential-thinking,
slack) are proxied through `uvx mcp-compressor`. The compressor
exposes only two dispatcher tools per server -- `<server>_get_tool_schema`
and `<server>_invoke_tool` -- with an empty advertised inputSchema. The
schema is wrong; the dispatcher actually requires arguments.

To call any tool on these servers, supply the dispatcher args
explicitly:

- `<server>_get_tool_schema(tool_name="real_tool_name")` -> returns the
  real input schema for that backend tool.
- `<server>_invoke_tool(tool_name="real_tool_name", arguments={...})` ->
  invokes it with `arguments` as an inline object (NOT a JSON string,
  NOT flat keys, NOT `params` / `kwargs` / `input` / `name`).

The list of real tools available behind each dispatcher is in the
dispatcher's tool description (`Available tools are: <tool>...`). Read
the description before the first call; do not probe arg shapes.

If a call returns `-32602 missing tool_name`, you forgot `tool_name` -
the empty inputSchema is misleading you. Pass `tool_name` even though
it is not declared.
```

Why CLAUDE.md vs SessionStart hook:

- CLAUDE.md persists across sessions, surfaces in every conversation,
  no maintenance.
- A hook would inject the same text via SessionStart but adds a
  per-server matcher and timing risk (some flows skip hooks); CLAUDE.md
  is simpler and equivalent in effect.
- A description override via `--include-tools` would require listing
  every backend tool in `~/.claude.json` per server - high maintenance,
  and the schemas of the underlying tools still wouldn't surface
  upfront.

### Part 2 - file upstream issue

File a GitHub issue at `atlassian-labs/mcp-compressor` describing:

- `compressed-tools` mode publishes `inputSchema:
  {"type":"object","properties":{}}` for `*_get_tool_schema` and
  `*_invoke_tool` across all observed versions (0.18.1-0.23.0) and
  compression levels (low/high/medium/max).
- Recommended fix: dispatcher `inputSchema` should declare
  `tool_name` (required, string) and `arguments` (object, default
  `{}`). For `_get_tool_schema`, only `tool_name` required.
- Why it matters: schema-aware MCP clients (Claude Code, schema-aware
  SDKs) cannot discover the dispatcher contract and either fail
  outright or burn tokens probing shapes. Empty `properties` invites
  the LLM to call with `{}`, which the server then rejects.
- Include the reproduction (probe transcript from this design).

Out of scope: opening the PR ourselves. The reproduction is enough
signal; let the maintainers choose the fix.

## Non-goals

- Do NOT drop the compressor wrapper. The wrapping is doing real work
  (token compression), and once the hint is in place the dispatcher
  is usable.
- Do NOT change `bin/.local/bin/mcp-add`. It produces the correct
  invocation; only the upstream schema is wrong.
- Do NOT add env vars to `~/.claude.json` "env" blocks. The current
  session confirmed shell env inheritance works (slack returned real
  channels using shell-exported `SLACK_BOT_TOKEN`).
- Do NOT touch `ghostty/.config/ghostty/config` (unrelated dirty file
  in `git status`).

## Files touched

1. `claude/.claude/CLAUDE.md` - add the "MCP servers wrapped by
   mcp-compressor" section.

(Upstream issue lives on GitHub, not in this repo.)

## Verification

1. Confirm the stow symlink resolves to the updated file:
   `readlink /Users/ben/.claude/CLAUDE.md` ->
   `../workspace/dotfiles/claude/.claude/CLAUDE.md`. No `claude-sync`
   needed (CLAUDE.md is stowed, not generated).
2. Open a fresh Claude Code session; ask it to list Slack channels.
   First dispatcher call should include `tool_name="slack_list_channels"`
   without trial-and-error.
3. Repeat for atlassian (`jira_search` or `jira_get_issue`), qmd
   (`query` or `status`), sequential-thinking (`sequentialthinking`).
4. Confirm GitHub issue filed and referenced in commit message.

## Rollback

Revert the CLAUDE.md commit. No state outside the file changes.

## Open questions

- None for scope. Wording of the CLAUDE.md section can be tightened
  during plan execution if Claude voice/length norms in the file
  prefer terser prose.
