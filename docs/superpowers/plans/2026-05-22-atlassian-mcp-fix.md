> **RETRACTED 2026-05-22** — implements the retracted 0.22.0-pin design. See `docs/superpowers/plans/2026-05-22-atlassian-mcp-drop-compressor.md` for the corrected plan.

---

# Atlassian MCP fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin mcp-compressor to 0.22.0 in `mcp-add` so wrapped MCP servers (especially atlassian) recover required-argument passthrough that 0.23.0 broke.

**Architecture:** Inject a `MCP_COMPRESSOR_VERSION` constant (env-overridable, default `0.22.0`) into the `mcp-add` shell wrapper and pass it through to `uvx --from mcp-compressor==<ver>`. Document the pin in CLAUDE.md so future sessions know which version is held and how to unpin. Regeneration of the four wrapped entries in `~/.claude.json` is performed by the operator after merge using procedures captured in the spec - not by the plan, because `~/.claude.json` is gitignored and Claude must be restarted for new entries to take effect.

**Tech Stack:** Bash (`bin/.local/bin/mcp-add`), GNU Stow (package layout), Markdown (CLAUDE.md), `uvx` from `uv` (Python tool runner). No language test runner involved - the wrapper is shell glue and manual verification post-restart is the only check available.

**Spec:** `docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md` (commit `bc0fa3f`).

---

## File map

- Modify: `bin/.local/bin/mcp-add` - inject version pin constant and `--from` flag into the two `exec claude mcp add` branches.
- Modify: `claude/.claude/CLAUDE.md` - append a "### Version pin" subsection to the existing `## MCP servers wrapped by mcp-compressor` section.

No new files. No test files (no existing test harness for `mcp-add`; manual verification only).

---

## Task 1: Preflight - confirm `mcp-compressor==0.22.0` resolves

**Goal:** Sanity-check that 0.22.0 is still on PyPI and that the proposed `uvx --from ...` invocation actually picks the pinned version before we change `mcp-add`. If 0.22.0 is yanked or otherwise unresolvable, the plan needs to switch to a different pinned version and this task surfaces that immediately.

**Files:** none.

- [ ] **Step 1: Run the pinned uvx form**

Run:

```sh
uvx --from "mcp-compressor==0.22.0" mcp-compressor --version
```

Expected output (exact):

```
mcp-compressor 0.22.0
```

If the output is `mcp-compressor 0.23.0` or any other version, the cache or PyPI resolution is wrong - stop and investigate before continuing.

If `uvx` errors with something like `No solution found when resolving tool dependencies`, 0.22.0 has been removed from PyPI; pick the next-most-recent version that pre-dates `2026-05-21 21:50:57 UTC` (the 0.23.0 upload timestamp) and use it as the pinned constant in Task 2.

- [ ] **Step 2: No commit**

This task changes no files. Move to Task 2.

---

## Task 2: Pin `mcp-compressor` version in `mcp-add`

**Goal:** Add an env-overridable `MCP_COMPRESSOR_VERSION` constant defaulting to `0.22.0` and thread it into both `exec claude mcp add ...` branches as `uvx --from "mcp-compressor==$MCP_COMPRESSOR_VERSION" mcp-compressor ...`.

**Files:**
- Modify: `bin/.local/bin/mcp-add` (full current content shown below).

Current file (for reference - do not paste, use Edit):

```bash
#!/usr/bin/env bash
# mcp-add: Add an MCP server wrapped with mcp-compressor
#
# Usage:
#   mcp-add [-s <scope>] <name> <url>           # HTTP/SSE server
#   mcp-add [-s <scope>] <name> -- <cmd> [args] # stdio server
#
# Scopes (same as `claude mcp add --scope`):
#   user    (default) — available in all projects for this user
#   project           — stored in .mcp.json, shared with the repo
#   local             — stored in .mcp.json.local, not committed
set -euo pipefail

SCOPE="user"
while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
        -s|--scope)
            SCOPE="$2"
            case "$SCOPE" in user|project|local) ;; *) echo "Invalid scope: $SCOPE (must be user, project, or local)" >&2; exit 1 ;; esac
            shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[[ $# -lt 2 ]] && {
    echo "Usage: mcp-add [-s user|project|local] <name> <url>" >&2
    echo "       mcp-add [-s user|project|local] <name> -- <cmd> [args]" >&2
    exit 1
}

NAME="$1"; shift

if [[ "$1" == "--" ]]; then
    shift
    exec claude mcp add --scope "$SCOPE" "$NAME" -- \
        uvx mcp-compressor --server-name "$NAME" -- "$@"
else
    exec claude mcp add --scope "$SCOPE" "$NAME" -- \
        uvx mcp-compressor --server-name "$NAME" "$1"
fi
```

- [ ] **Step 1: Insert the version constant**

Use Edit. Replace the line `set -euo pipefail` with:

```bash
set -euo pipefail

# Pin mcp-compressor to a known-good release. 0.23.0 (PyPI 2026-05-21)
# regressed required-argument passthrough in compressed-tools mode -
# the backend receives input_value={} and rejects every call carrying
# required arguments. See:
#   docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md
# Override per-invocation with MCP_COMPRESSOR_VERSION=<ver>.
MCP_COMPRESSOR_VERSION="${MCP_COMPRESSOR_VERSION:-0.22.0}"
```

- [ ] **Step 2: Pin the stdio branch**

Use Edit. Replace:

```bash
    exec claude mcp add --scope "$SCOPE" "$NAME" -- \
        uvx mcp-compressor --server-name "$NAME" -- "$@"
```

with:

```bash
    exec claude mcp add --scope "$SCOPE" "$NAME" -- \
        uvx --from "mcp-compressor==$MCP_COMPRESSOR_VERSION" \
        mcp-compressor --server-name "$NAME" -- "$@"
```

- [ ] **Step 3: Pin the HTTP/SSE branch**

Use Edit. Replace:

```bash
    exec claude mcp add --scope "$SCOPE" "$NAME" -- \
        uvx mcp-compressor --server-name "$NAME" "$1"
```

with:

```bash
    exec claude mcp add --scope "$SCOPE" "$NAME" -- \
        uvx --from "mcp-compressor==$MCP_COMPRESSOR_VERSION" \
        mcp-compressor --server-name "$NAME" "$1"
```

- [ ] **Step 4: Syntax-check the script**

Run:

```sh
bash -n /Users/ben/workspace/dotfiles/.claude/worktrees/atlassian-mcp-fix/bin/.local/bin/mcp-add
```

Expected output: (empty - exit code 0)

If the command prints a parse error, fix the indentation or line-continuation backslash that caused it and re-run.

- [ ] **Step 5: Verify the env override path is honored**

Run:

```sh
MCP_COMPRESSOR_VERSION=0.23.0 bash -c '
  set -euo pipefail
  MCP_COMPRESSOR_VERSION="${MCP_COMPRESSOR_VERSION:-0.22.0}"
  echo "resolved: $MCP_COMPRESSOR_VERSION"
'
```

Expected output:

```
resolved: 0.23.0
```

Then re-run without the env var:

```sh
bash -c '
  set -euo pipefail
  MCP_COMPRESSOR_VERSION="${MCP_COMPRESSOR_VERSION:-0.22.0}"
  echo "resolved: $MCP_COMPRESSOR_VERSION"
'
```

Expected output:

```
resolved: 0.22.0
```

This confirms the env-override pattern works exactly as written in the script.

- [ ] **Step 6: Commit**

```sh
git add bin/.local/bin/mcp-add
git commit -m "$(cat <<'EOF'
fix(bin): pin mcp-compressor to 0.22.0 in mcp-add

0.23.0 (PyPI 2026-05-21) regressed required-argument passthrough in
compressed-tools mode; backend receives input_value={} for any call
with required args. Reproduced today against mcp-atlassian
jira_get_issue and jira_get_user_profile.

MCP_COMPRESSOR_VERSION env var overrides the default for future
testing of newer releases without editing the script.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected git status after commit: working tree clean (no staged or unstaged changes).

---

## Task 3: Document the pin in CLAUDE.md

**Goal:** Append a "### Version pin" subsection under the existing `## MCP servers wrapped by mcp-compressor` section in `claude/.claude/CLAUDE.md` so every future session sees the pin policy without having to find the spec.

**Files:**
- Modify: `claude/.claude/CLAUDE.md`.

- [ ] **Step 1: Locate the insertion point**

Run:

```sh
grep -n '^## MCP servers wrapped by mcp-compressor' \
  /Users/ben/workspace/dotfiles/.claude/worktrees/atlassian-mcp-fix/claude/.claude/CLAUDE.md
```

Expected: one match on a line number `N`. The new subsection goes at the end of that section, just before the next `## ` heading (which is `## Git Workflow` in the current file). Use Read to fetch the lines between `N` and the next `## ` so you have an exact `old_string` anchor for Edit.

- [ ] **Step 2: Append the subsection**

Find the last paragraph of the `## MCP servers wrapped by mcp-compressor` section (currently ending with the sentence about `-32602 missing tool_name`). Use Edit to append the following block immediately after that paragraph and before the next `## ` heading. Anchor on the closing sentence of the existing section to keep the Edit unambiguous.

Block to append (one blank line before, one blank line after):

````markdown
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
````

- [ ] **Step 3: Verify the subsection rendered cleanly**

Run:

```sh
grep -nA2 '^### Version pin' \
  /Users/ben/workspace/dotfiles/.claude/worktrees/atlassian-mcp-fix/claude/.claude/CLAUDE.md
```

Expected: the heading appears exactly once, and the two lines after it match the opening of the block above.

Also run:

```sh
awk '
  /^## MCP servers wrapped by mcp-compressor/ {in_section=1; next}
  /^## / && in_section {print NR": next-section "$0; exit}
  in_section
' /Users/ben/workspace/dotfiles/.claude/worktrees/atlassian-mcp-fix/claude/.claude/CLAUDE.md | tail
```

Expected: the tail of the section shows the new "### Version pin" subsection ending just before `next-section ## Git Workflow`. If the new block landed inside the wrong section or after `## Git Workflow`, the Edit anchor was wrong - revert and re-do Step 2 with a tighter anchor.

- [ ] **Step 4: Commit**

```sh
git add claude/.claude/CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(claude): document mcp-compressor 0.22.0 pin policy

Captures the pin reason, the env-override knob, and the bump
procedure (mcp-add constant change + regeneration steps in
docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected git status after commit: working tree clean.

---

## Verification (operator runs post-merge)

Not a task in this plan - documented here as a checklist for the operator. None of these steps run in the worktree; all happen after merge to `main` and a Claude restart.

1. Regenerate the four wrapped `~/.claude.json` entries (full commands in the spec, "Part 2" section).
2. Restart Claude Code.
3. Confirm `jq '.mcpServers.atlassian.args | join(" ")' ~/.claude.json` includes `--from mcp-compressor==0.22.0`.
4. Confirm `uvx --from mcp-compressor==0.22.0 mcp-compressor --version` prints `mcp-compressor 0.22.0`.
5. In a fresh Claude session: `mcp__atlassian__atlassian_invoke_tool(tool_name="jira_get_issue", arguments={"issue_key":"INFRA-362"})` returns an issue payload.
6. In the same session: `mcp__atlassian__atlassian_invoke_tool(tool_name="jira_get_user_profile", arguments={"user_identifier":"ben.kim@greenenergytrading.com.au"})` returns a profile.
7. In the same session: `mcp__slack__slack_invoke_tool(tool_name="slack_list_channels", arguments={"limit":3})` still returns a channel list.

Any of items 5-7 returning the `Missing required argument [type=missing_argument, input_value={}, input_type=dict]` error means the pin did not take effect; check that `~/.claude.json` was actually regenerated and that the Claude restart happened.

---

## Out-of-plan follow-ups

- Update memory file `reference_atlassian_dispatcher_bug.md` (outside this repo, under `~/.claude/projects/-Users-ben-workspace-dotfiles/memory/`) to point at the 0.23.0 regression specifically and link to the new spec, after merge.
- Capture the fix as a solutions doc under `docs/solutions/developer-experience/atlassian-mcp-fix-2026-05-22.md` via `ce-compound` after implementation, per the canonical workflow.
