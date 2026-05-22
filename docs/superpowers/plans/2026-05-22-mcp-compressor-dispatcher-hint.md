# mcp-compressor Dispatcher Hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach fresh Claude sessions the `tool_name`+`arguments` dispatcher shape required by mcp-compressor-wrapped MCP servers, by adding an authoritative section to the always-loaded global CLAUDE.md, and file an upstream issue against `atlassian-labs/mcp-compressor` for the empty-inputSchema design flaw.

**Architecture:** Two-part fix.
(1) Edit `claude/.claude/CLAUDE.md` to add a section after the existing `## Semantic Search (qmd)` block (line 43) and before `## Git Workflow` (line 45). The file is stowed to `~/.claude/CLAUDE.md`, which Claude Code loads at session start.
(2) Create a GitHub issue at `atlassian-labs/mcp-compressor` documenting the empty `inputSchema` for `*_get_tool_schema`/`*_invoke_tool` across versions 0.18.1-0.23.0 and all compression levels, with reproduction transcript.

**Tech Stack:** Markdown (CLAUDE.md), GitHub CLI (`gh`).

---

## File Structure

| Path | Action | Responsibility |
|------|--------|----------------|
| `claude/.claude/CLAUDE.md` | Modify (insert ~25-line section between lines 43 and 45) | Always-loaded instruction file. New section teaches dispatcher arg shape. |
| GitHub issue at `atlassian-labs/mcp-compressor` | Create (external) | Track empty-`inputSchema` bug upstream. |

No new files in this repo. No code changes. No tests to write (this is a documentation + upstream-tracking change; verification is a manual smoke test in a fresh session).

---

## Task 1: Add MCP-compressor dispatcher section to CLAUDE.md

**Files:**
- Modify: `claude/.claude/CLAUDE.md` (insert between line 43 and line 45)

- [ ] **Step 1: Verify insertion point**

Run:

```bash
sed -n '40,48p' claude/.claude/CLAUDE.md
```

Expected output (the qmd section's last line is line 43; line 44 is blank; line 45 begins `## Git Workflow`):

```
- You need to find all occurrences exhaustively (refactoring, renaming)

Never automate `qmd collection add`, `qmd embed`, or `qmd update` --
indexing is always a manual user action.

## Git Workflow

All work happens on isolated worktree branches. Hooks enforce worktree
```

- [ ] **Step 2: Insert the new section**

Use Edit to replace:

```
Never automate `qmd collection add`, `qmd embed`, or `qmd update` --
indexing is always a manual user action.

## Git Workflow
```

with:

```
Never automate `qmd collection add`, `qmd embed`, or `qmd update` --
indexing is always a manual user action.

## MCP servers wrapped by mcp-compressor

Four servers in `~/.claude.json` (atlassian, qmd, sequential-thinking,
slack) are proxied through `uvx mcp-compressor`. The compressor exposes
only two dispatcher tools per server -- `<server>_get_tool_schema` and
`<server>_invoke_tool` -- with an empty advertised inputSchema. The
schema is wrong; the dispatcher actually requires arguments.

To call any tool on these servers, supply the dispatcher args
explicitly:

- `<server>_get_tool_schema(tool_name="real_tool_name")` -- returns the
  real input schema for that backend tool.
- `<server>_invoke_tool(tool_name="real_tool_name", arguments={...})`
  -- invokes it. `arguments` is an inline object, NOT a JSON string,
  NOT flat keys at the dispatcher level, NOT `params` / `kwargs` /
  `input` / `name`.

The list of real tools available behind each dispatcher is in the
dispatcher's own tool description (`Available tools are: <tool>...`).
Read the description before the first call; do not probe arg shapes.

If a call returns `-32602 missing tool_name`, you forgot `tool_name` --
the empty inputSchema is misleading you. Pass `tool_name` even though
it is not declared.

## Git Workflow
```

- [ ] **Step 3: Verify the edit took**

Run:

```bash
sed -n '45,73p' claude/.claude/CLAUDE.md
```

Expected: shows the new `## MCP servers wrapped by mcp-compressor` heading on line 45 and the `## Git Workflow` heading further down (around line 73).

Then verify the live symlink resolves to the worktree file:

```bash
readlink /Users/ben/.claude/CLAUDE.md
```

Expected: `../workspace/dotfiles/claude/.claude/CLAUDE.md` (points to the main branch copy, not the worktree -- this is fine; the change lives on the worktree branch until merged).

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/CLAUDE.md
git commit -m "docs(claude): teach mcp-compressor dispatcher arg shape

Fresh sessions waste calls probing arg shapes against the four
compressor-wrapped MCP servers (atlassian, qmd, sequential-thinking,
slack) because the dispatcher's inputSchema is published as empty
{type: object, properties: {}} despite requiring tool_name+arguments.
Document the correct shape so the LLM gets it right on the first call.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds. `git log --oneline -1` shows the new commit.

---

## Task 2: File upstream issue against atlassian-labs/mcp-compressor

**Files:**
- Create (external): GitHub issue at https://github.com/atlassian-labs/mcp-compressor

- [ ] **Step 1: Draft the issue body to a temp file**

Use Write to create a temp file at `/tmp/mcp-compressor-issue.md` (NOT inside the repo) with this body:

```markdown
## Summary

In `compressed-tools` mode, the two dispatcher tools per backend
(`<server>_get_tool_schema`, `<server>_invoke_tool`) advertise
`inputSchema: {"type": "object", "properties": {}}` over MCP, even
though the server requires a `tool_name` (string) argument and
`_invoke_tool` additionally requires `arguments` (object).

This breaks schema-aware MCP clients (Anthropic Claude Code among
others). The LLM sees an empty schema, calls the dispatcher with no
arguments, and the compressor returns:

```
MCP error -32602: missing tool_name
```

Even sophisticated agents waste many calls cycling through wrong arg
shapes before discovering the right one.

## Reproduction

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | uvx mcp-compressor==0.23.0 --server-name probe -- \
      npx -y @modelcontextprotocol/server-sequential-thinking
```

Returned `inputSchema` for `probe_get_tool_schema` and `probe_invoke_tool`:

```json
{"type": "object", "properties": {}}
```

Reproduced against `mcp-compressor==0.18.1`, `0.20.0`, `0.22.0`,
`0.23.0` and against all four compression levels (`low`, `high`,
`medium`, `max`). Not specific to a backend; same shape regardless of
whether the wrapped backend is sequential-thinking, slack, atlassian,
or qmd.

## Expected behavior

Dispatcher `inputSchema` should declare the contract:

- `<server>_get_tool_schema`: `tool_name` (string, required).
- `<server>_invoke_tool`: `tool_name` (string, required) and
  `arguments` (object, default `{}`).

Then schema-aware clients can call the dispatcher correctly on the
first attempt.

## Environment

- `mcp-compressor` 0.18.1-0.23.0 (Rust binary, Python wheel)
- macOS 14, Darwin 24.6.0, arm64
- Client: Anthropic Claude Code (strict schema enforcement)
```

- [ ] **Step 2: Verify the temp file**

Run:

```bash
wc -l /tmp/mcp-compressor-issue.md && head -3 /tmp/mcp-compressor-issue.md
```

Expected: ~60 lines; first lines are `## Summary` and an empty line.

- [ ] **Step 3: File the issue**

Confirm with the user before posting. This is an external-facing action (creates a public GitHub issue under user's identity).

After user confirms, run:

```bash
gh issue create \
  --repo atlassian-labs/mcp-compressor \
  --title "compressed-tools dispatcher publishes empty inputSchema, breaks schema-aware clients" \
  --body-file /tmp/mcp-compressor-issue.md
```

Expected: prints the new issue URL (e.g. `https://github.com/atlassian-labs/mcp-compressor/issues/NNN`). Capture this URL for Step 4.

- [ ] **Step 4: Record the upstream issue reference in the repo**

Append a short reference line to the design spec (`docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md`) so the upstream link survives in repo history.

Use Edit to replace:

```
## Rollback

Revert the CLAUDE.md commit. No state outside the file changes.
```

with:

```
## Rollback

Revert the CLAUDE.md commit. No state outside the file changes.

## Upstream issue

Filed: <URL from Step 3>
```

- [ ] **Step 5: Commit the spec update**

```bash
git add docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md
git commit -m "docs(claude): record upstream mcp-compressor issue URL

Reference the filed atlassian-labs/mcp-compressor issue from the
brainstorm spec so the link survives in repo history alongside the
local hint fix.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: Clean up temp file**

```bash
rm /tmp/mcp-compressor-issue.md
```

---

## Task 3: Verification in a fresh session (manual)

**Files:** none modified.

- [ ] **Step 1: Merge the worktree to main**

Per the dotfiles `no-pr` workflow:

```bash
git checkout main
git merge --no-ff worktree-mcp-compressor-dispatcher-hint
git push origin main
```

(If staying on the worktree for further work, defer this step until after the smoke test.)

- [ ] **Step 2: Open a fresh Claude Code session**

In a new terminal:

```bash
cd ~/workspace/dotfiles
claude
```

- [ ] **Step 3: Smoke-test each wrapped server**

In the fresh session, ask Claude:

```
List 3 Slack channels using mcp__slack.
```

Expected: Claude's first dispatcher call includes
`tool_name="slack_list_channels"` and `arguments={"limit": 3}` (or
similar with `limit` set) -- no probing through `name` / `params` /
`arguments_json` / etc. Channels return.

Repeat with:

```
Use mcp__atlassian to fetch issue INFRA-362.
```

Expected: first call uses
`tool_name="jira_get_issue"`, `arguments={"issue_key": "INFRA-362"}`.

```
Use mcp__qmd to show the index status.
```

Expected: first call uses `tool_name="status"`, `arguments={}`.

```
Use mcp__sequential-thinking to think about: "1+1".
```

Expected: first call uses `tool_name="sequentialthinking"`, `arguments={...}` with the required `thought`/`nextThoughtNeeded`/`thoughtNumber`/`totalThoughts` fields.

- [ ] **Step 4: Confirm verification**

If all four servers worked on the first dispatcher call, mark this plan complete. If any of them probed shapes (called with `name` or `params` or flat keys before settling on `tool_name`+`arguments`), the hint needs sharper wording -- re-open the spec, refine, and re-commit.

---

## Self-Review

**Spec coverage:**

- "Part 1: session-resident hint" -> Task 1 (CLAUDE.md insertion + commit). Covered.
- "Part 2: file upstream issue" -> Task 2 (gh issue create + spec ref). Covered.
- "Verification" steps 1-4 in spec -> Task 3. Covered (skipped `claude-sync` per spec correction).
- "Rollback" -> "revert the CLAUDE.md commit". Implicit in Task 1's atomicity (single-file commit). Not a task step, but trivially achievable via `git revert <commit>`.
- "Non-goals" (don't drop wrapper, don't touch mcp-add, don't touch ghostty file, don't change env blocks) -> respected; no task touches those.

**Placeholder scan:** no TBD/TODO. All commit messages, commands, and section text are concrete.

**Type consistency:** the hint uses `<server>_get_tool_schema` and `<server>_invoke_tool` consistently (spec previously had `<name>` in one place; fixed during spec self-review). The `arguments` parameter is referred to consistently as "inline object" everywhere.

**One known soft edge:** Task 3 Step 1 says "merge the worktree to main" but is optional ("defer if staying on worktree"). The downstream verification (Step 2-4) can run from a fresh session in *any* directory because CLAUDE.md is loaded globally; the smoke test only requires the change to have landed on the file Claude Code reads from, which after merge is `~/.claude/CLAUDE.md` -> `dotfiles/claude/.claude/CLAUDE.md`. While still on the worktree branch, the symlink points to the *main-branch* CLAUDE.md, so fresh sessions wouldn't see the hint until merge. Document this in commit history rather than belabor it here.
