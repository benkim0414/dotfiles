# Drop mcp-compressor wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop `uvx mcp-compressor` wrapper from all four wrapped MCP servers (`atlassian`, `qmd`, `sequential-thinking`, `slack`), remove the `mcp-add` helper, retract the prior 0.22.0-pin docs in place, and capture the empty-schema learning.

**Architecture:** Repo-side: delete `bin/.local/bin/mcp-add`, prune the `## MCP servers wrapped by mcp-compressor` section from `claude/.claude/CLAUDE.md`, prepend RETRACTED headers to four prior spec/plan/solution docs, write one new learning doc. Out-of-repo: operator regenerates the four `~/.claude.json` entries with `claude mcp remove` + `claude mcp add ... -- <raw backend>` after merge and restarts Claude.

**Tech Stack:** Bash (`bin/.local/bin/mcp-add` removal), Markdown (CLAUDE.md, specs, plans, solutions), GNU Stow (re-stow `bin` to drop dangling symlink). No language test runner — verification is `grep` + manual restart check post-merge.

---

## File Structure

Files modified or created on this branch:

- Delete: `bin/.local/bin/mcp-add`
- Modify: `claude/.claude/CLAUDE.md` (replace lines 45-89, the wrapped-servers section)
- Modify: `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md` (prepend RETRACTED header)
- Modify: `docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md` (prepend RETRACTED header)
- Modify: `docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md` (prepend RETRACTED header)
- Modify: `docs/solutions/developer-experience/mcp-compressor-dispatcher-hint-2026-05-22.md` (prepend RETRACTED header)
- Modify: `docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md` (prepend RETRACTED header)
- Create: `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md` (learning doc)

Out-of-repo (manual, post-merge):
- `~/.claude.json` regeneration via `claude mcp remove` + `claude mcp add`.
- `~/.claude/projects/-Users-ben-workspace-dotfiles/memory/reference_atlassian_dispatcher_bug.md` body rewrite.
- Claude Code restart.

---

## Task 1: Retract prior specs/plans/solutions

**Files:**
- Modify: `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md`
- Modify: `docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md`
- Modify: `docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md`
- Modify: `docs/solutions/developer-experience/mcp-compressor-dispatcher-hint-2026-05-22.md`
- Modify: `docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md`

- [ ] **Step 1: Prepend RETRACTED header to fix design doc**

Insert at line 1 of `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md`:

```markdown
> **RETRACTED 2026-05-22** — the 0.22.0-pin hypothesis was wrong. The compressor's `compressed-tools` mode advertises empty `inputSchema`, and Claude Code's MCP client strips non-declared `arguments` keys before forwarding, so required-arg calls were never delivered to the backend on any compressor version. Resolution: drop the wrapper entirely. See `docs/superpowers/specs/2026-05-22-atlassian-mcp-drop-compressor-design.md` and `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`. The body below is preserved for audit.

---

```

- [ ] **Step 2: Prepend RETRACTED header to fix plan**

Insert at line 1 of `docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md`:

```markdown
> **RETRACTED 2026-05-22** — implements the retracted 0.22.0-pin design. See `docs/superpowers/plans/2026-05-22-atlassian-mcp-drop-compressor.md` for the corrected plan.

---

```

- [ ] **Step 3: Prepend RETRACTED header to dispatcher-hint design**

Insert at line 1 of `docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md`:

```markdown
> **RETRACTED 2026-05-22** — the hint instructed callers to pass `arguments` as the magic key. Raw stdio bisect later proved the magic key is actually `tool_input`, but Claude Code strips both before they reach the compressor (empty `inputSchema` + strict validator). The CLAUDE.md hint that this spec produced has been removed. See `docs/superpowers/specs/2026-05-22-atlassian-mcp-drop-compressor-design.md` and `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`.

---

```

- [ ] **Step 4: Prepend RETRACTED header to dispatcher-hint solution**

Insert at line 1 of `docs/solutions/developer-experience/mcp-compressor-dispatcher-hint-2026-05-22.md`:

```markdown
> **RETRACTED 2026-05-22** — supersedes by `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`. The hint approach was abandoned when the compressor wrapper was dropped entirely.

---

```

- [ ] **Step 5: Prepend RETRACTED header to arg-passthrough solution**

Insert at line 1 of `docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md`:

```markdown
> **RETRACTED 2026-05-22** — attributes the failure to a 0.23.0 regression. Later bisect (0.10.0 through 0.23.0) showed every available release exhibits the same `input_value={}` symptom via Claude, because the root cause is the empty-schema dispatcher pattern, not a version-specific change. See `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`.

---

```

- [ ] **Step 6: Verify all five files start with a RETRACTED header**

Run:

```sh
for f in \
  docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md \
  docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md \
  docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md \
  docs/solutions/developer-experience/mcp-compressor-dispatcher-hint-2026-05-22.md \
  docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md; do
  head -1 "$f"
done
```

Expected: each line begins with `> **RETRACTED 2026-05-22**`.

- [ ] **Step 7: Commit**

```sh
git add docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md \
        docs/superpowers/plans/2026-05-22-atlassian-mcp-fix.md \
        docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md \
        docs/solutions/developer-experience/mcp-compressor-dispatcher-hint-2026-05-22.md \
        docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md
git commit -m "docs(mcp-compressor): retract 0.22.0-pin and dispatcher-hint docs

The pin hypothesis and the arguments-key hint were both wrong.
Empty-schema dispatcher + Claude strict validator drops required
args regardless of compressor version or arg shape. New design and
learning supersede these docs; bodies preserved for audit."
```

---

## Task 2: Prune CLAUDE.md `MCP servers wrapped by mcp-compressor` section

**Files:**
- Modify: `claude/.claude/CLAUDE.md` (replace lines 45-89)

- [ ] **Step 1: Read current section bounds**

The section starts at the heading `## MCP servers wrapped by mcp-compressor` (line 45) and ends at the blank line before `## Git Workflow` (line 90). Replace everything from line 45 through line 89 (inclusive) with a shorter note.

- [ ] **Step 2: Apply the replacement**

Replace the block:

```text
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

### Version pin

`mcp-add` pins `mcp-compressor` to 0.22.0 via
`uvx --from mcp-compressor==0.22.0`. 0.23.0 (PyPI 2026-05-21) regressed
required-argument passthrough in `compressed-tools` mode - the backend
receives `input_value={}` and rejects every call carrying required
arguments. Reproduced against `mcp-atlassian` (`jira_get_issue`,
`jira_get_user_profile`) on 2026-05-22.

To test a newer release without editing `mcp-add`:

```sh
MCP_COMPRESSOR_VERSION=0.24.0 mcp-add <name> -- <cmd>
```

To bump the default after upstream fixes the regression, change the
constant in `bin/.local/bin/mcp-add` and re-run the regeneration
procedure documented in
`docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md`.
```

with:

```text
## MCP servers (atlassian, qmd, sequential-thinking, slack)

These four `~/.claude.json` servers run as raw backends. An earlier
attempt to wrap them with `uvx mcp-compressor` (transform mode
`compressed-tools`) was reverted on 2026-05-22 because the compressor
advertises empty `inputSchema` for its dispatcher tools and Claude
Code's MCP client strips non-declared keys from `arguments` before
forwarding, so every required-arg call reached the backend with `{}`.
Symptom was a pydantic `Missing required argument [input_value={}]`
error from `mcp-atlassian`. Root cause is structural, not version-
specific. See
`docs/superpowers/specs/2026-05-22-atlassian-mcp-drop-compressor-design.md`
and
`docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`.

The repo no longer carries the `mcp-add` wrapper helper. Add new MCP
servers with `claude mcp add --scope user <name> -- <command>`
directly.
```

- [ ] **Step 3: Verify no remaining references to `mcp-add` or `mcp-compressor==0.22.0` in CLAUDE.md**

Run:

```sh
grep -n "mcp-add\|mcp-compressor==0.22.0\|MCP_COMPRESSOR_VERSION" claude/.claude/CLAUDE.md
```

Expected: empty output.

- [ ] **Step 4: Commit**

```sh
git add claude/.claude/CLAUDE.md
git commit -m "docs(claude): drop mcp-compressor wrapper section

The compressor dispatcher's empty inputSchema is incompatible with
Claude Code's strict-validator MCP client. Replace the wrapped-
servers guidance and the 0.22.0 version-pin subsection with a
shorter note pointing at the drop-compressor design and learning."
```

---

## Task 3: Delete `bin/.local/bin/mcp-add`

**Files:**
- Delete: `bin/.local/bin/mcp-add`

- [ ] **Step 1: Confirm no other source-tree references**

Run:

```sh
grep -rn "mcp-add" --include="*.sh" --include="*.json" --include="*.toml" bin/ claude/ 2>/dev/null
```

Expected: no source references (markdown matches in `docs/` already retracted).

- [ ] **Step 2: Delete the script**

```sh
git rm bin/.local/bin/mcp-add
```

- [ ] **Step 3: Verify deletion**

```sh
ls bin/.local/bin/mcp-add 2>&1
```

Expected: `ls: bin/.local/bin/mcp-add: No such file or directory`.

- [ ] **Step 4: Commit**

```sh
git commit -m "chore(mcp-add): remove mcp-compressor wrapper helper

No remaining wrapped MCP servers. The helper's sole purpose was to
emit \`uvx --from mcp-compressor==... mcp-compressor --server-name
... -- <cmd>\` invocations. Replaced by direct
\`claude mcp add --scope user <name> -- <cmd>\` calls."
```

---

## Task 4: Write the empty-schema learning doc

**Files:**
- Create: `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`

- [ ] **Step 1: Write the doc**

Content:

```markdown
---
module: mcp-compressor
tags: [mcp, compressor, claude-code, schema-validation, debugging]
problem_type: integration-issue
---

# mcp-compressor compressed-tools mode is incompatible with Claude Code for required-arg tools

## Problem

Calling any required-arg tool on an MCP server wrapped by
`uvx mcp-compressor` (transform mode `compressed-tools`) through Claude
Code produced a pydantic validation error from the backend:

```
1 validation error for call[get_user_profile]
user_identifier
  Missing required argument [type=missing_argument, input_value={}, input_type=dict]
```

The backend received an empty argument dict regardless of how the
caller serialised `arguments`, on every available compressor release
from 0.10.0 through 0.23.0.

## Root cause

The compressor's `compressed-tools` mode exposes two dispatcher tools
per backend (`<server>_get_tool_schema`, `<server>_invoke_tool`) with
the following advertised schema:

```json
{ "type": "object", "properties": {} }
```

Claude Code's MCP client validates the `arguments` payload of a
`tools/call` request against the advertised `inputSchema` and strips
any key that is not declared in `properties`. Because the dispatcher
declares no properties, every key the caller supplies is stripped
before the request reaches the compressor. The compressor sees an
empty arguments dict and forwards an empty dict to the backend, which
fails required-arg validation.

A raw stdio bisect (spawning
`uvx --from mcp-compressor==X.Y.Z mcp-compressor --server-name atlassian
-- uvx mcp-atlassian` directly, sending `tools/call` JSON-RPC, and
observing the backend response) showed that the actual magic key for
`invoke_tool` is `tool_input`, not `arguments`. Raw stdio calls with
`tool_input` succeed against the backend on every compressor version
tested. Through Claude Code, both `arguments` and `tool_input` are
stripped because neither is declared in the empty schema.

The `get_tool_schema` path appears to work through Claude only because
the compressor handles `tool_name` locally without forwarding the
arguments dict to the backend; the bug is invisible until the caller
needs to actually invoke a backend tool with required parameters.

## Investigation method

Stdio bisect script (Python). Launch each compressor version directly,
send `initialize` plus a `tools/call` invoking
`jira_get_user_profile(user_identifier="x@example.com")`, observe the
backend's response payload. Useful argument-shape variants to try:

1. Nested: `arguments={"tool_name": ..., "arguments": {...}}`
2. Flat: `arguments={"tool_name": ..., "user_identifier": ...}`
3. Wrapper: `arguments={"tool_name": ..., "tool_input": {...}}`
4. JSON-string: `arguments={"tool_name": ..., "arguments": "{...}"}`

If the backend responds with a domain-specific error (e.g. "Could not
resolve email") the arguments reached it. If the backend responds with
`Missing required argument [input_value={}]`, the wrapper dropped them.

In `mcp-compressor` 0.22.0 only variant 3 (`tool_input`) reached the
backend. In 0.10.0 both 2 (flat) and 3 (`tool_input` was actually
parsed as nested-by-different-key) worked. The compressor's
expectations shifted across versions; the empty `inputSchema`
guarantees that no caller can hit them through Claude Code.

## Resolution

Drop the `uvx mcp-compressor` wrapper for any server that exposes
required-arg tools through Claude Code. Add the backend directly with
`claude mcp add --scope user <name> -- <command>`. Accept the token-
list size increase relative to the dispatcher pair — broken tool calls
cost more than verbose tool catalogs.

The token-compression benefit can be recovered in the future via:

- `cli` or `just-bash` transform modes (different interface, not yet
  evaluated through Claude Code).
- A custom proxy that advertises real per-tool schemas while still
  compressing the underlying payload.
- claude.ai-hosted MCP servers (Atlassian, Slack, etc.) which expose
  full schemas natively.

## Generalisable lesson

When an MCP server advertises a dispatcher tool with
`"properties": {}`, treat it as **unusable through Claude Code for any
backend tool that has required arguments**. The empty schema is a
contract that the dispatcher accepts no input, and Claude's MCP client
enforces that contract.

Verify a wrapper's dispatcher schema *before* adopting it, by running:

```sh
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}' \
  | <the wrapped command>
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | <the wrapped command>
```

If the dispatcher tools return `{"type":"object","properties":{}}`, the
wrapper will not work through Claude Code for required-arg calls.

## Related

- Retracted: `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md`
  (the 0.22.0-pin hypothesis).
- Retracted: `docs/superpowers/specs/2026-05-22-mcp-compressor-dispatcher-hint-design.md`
  (the `arguments`-magic-key hint).
- Retracted: `docs/solutions/integration-issues/mcp-compressor-arg-passthrough-regression-2026-05-22.md`
  (attributed the bug to a 0.23.0 regression).
- Current: `docs/superpowers/specs/2026-05-22-atlassian-mcp-drop-compressor-design.md`.
```

- [ ] **Step 2: Verify frontmatter is valid**

```sh
head -6 docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md
```

Expected:

```
---
module: mcp-compressor
tags: [mcp, compressor, claude-code, schema-validation, debugging]
problem_type: integration-issue
---
```

- [ ] **Step 3: Commit**

```sh
git add docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md
git commit -m "docs(mcp-compressor): add empty-schema learning

Captures the structural incompatibility between compressed-tools mode
and Claude Code's strict-schema MCP validator, the raw stdio bisect
method that proved version-independence, and the verification command
operators can run before adopting any MCP wrapper."
```

---

## Task 5: Restow `bin` to drop the dangling symlink

**Files:**
- No repo edits — runtime housekeeping only.

- [ ] **Step 1: Restow**

```sh
stow -t ~ -R bin
```

- [ ] **Step 2: Verify symlink is gone**

```sh
ls -la ~/.local/bin/mcp-add 2>&1
```

Expected: `ls: /Users/ben/.local/bin/mcp-add: No such file or directory`.

- [ ] **Step 3: Verify other bin scripts still resolve**

```sh
ls -la ~/.local/bin/mise-load-bw ~/.local/bin/claude-sync 2>&1 | head -4
```

Expected: both symlinks point into `bin/.local/bin/...` inside the dotfiles repo.

(No commit — stow operation is local.)

---

## Self-Review

**Spec coverage:**

- Spec Part 1 (regen `~/.claude.json`) → out-of-repo, captured in the post-merge procedure below; no plan task because the file is gitignored.
- Spec Part 2 (delete `mcp-add`) → Task 3, plus restow in Task 5.
- Spec Part 3 (prune CLAUDE.md) → Task 2.
- Spec Part 4 (memory rewrite) → out-of-repo, captured in post-merge procedure below.
- Spec Part 5 (retract prior specs/plans/solutions) → Task 1.
- Spec Part 6 (learning doc) → Task 4.

**Placeholder scan:** No TBDs, no "implement appropriately", every command and code block is concrete.

**Type consistency:** No types in this plan — docs and shell only.

---

## Post-merge procedure (operator runs, not part of plan tasks)

After this branch merges to `main`:

```sh
# 1. Regenerate the four MCP server entries in ~/.claude.json
for s in atlassian qmd sequential-thinking slack; do
  claude mcp remove --scope user "$s"
done
claude mcp add --scope user atlassian            -- uvx mcp-atlassian
claude mcp add --scope user qmd                  -- qmd mcp
claude mcp add --scope user sequential-thinking  -- npx -y @modelcontextprotocol/server-sequential-thinking
claude mcp add --scope user slack                -- npx -y @modelcontextprotocol/server-slack

# 2. Update the stale memory note in place
$EDITOR ~/.claude/projects/-Users-ben-workspace-dotfiles/memory/reference_atlassian_dispatcher_bug.md
# Replace body with the empty-schema root cause; keep the slug.

# 3. Restart Claude Code so the regenerated MCP entries take effect.
```

Post-restart verification:

```sh
jq '.mcpServers.atlassian.args' ~/.claude.json
# expected: ["mcp-atlassian"]
```

Then in a Claude session:

- `mcp__atlassian__jira_get_issue(issue_key="INFRA-362")` returns the issue payload.
- `mcp__atlassian__*_invoke_tool` and `*_get_tool_schema` tools are gone.
- Direct backend tools (`mcp__atlassian__jira_search`, etc.) appear.
