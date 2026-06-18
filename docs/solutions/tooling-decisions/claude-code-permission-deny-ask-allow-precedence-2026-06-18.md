---
title: "Claude Code permission precedence (ask beats allow) and overlay merge can add but not remove"
module: claude-code-permissions
date: 2026-06-18
problem_type: tooling_decision
component: tooling
related_components:
  - development_workflow
severity: medium
category: tooling-decisions
applies_when:
  - "configuring Claude Code permissions under defaultMode: auto"
  - "an allow rule and an ask rule both match the same tool call"
  - "splitting permission config between a committed base file and a merge-only overlay"
  - "auto-allowing MCP read tools while gating MCP write or destructive tools"
  - "writing MCP allow rules (server segment must be glob-free)"
root_cause: config_error
resolution_type: config_change
tags:
  - claude-code
  - permissions
  - mcp
  - settings-overlay
  - defaultmode-auto
  - claude-sync
  - precedence
---

# Claude Code permission precedence (ask beats allow) and overlay merge can add but not remove

## Context

Under Claude Code `defaultMode: auto`, unmatched tool calls go to a classifier,
but explicit `allow` entries skip it. We wanted two MCP servers (atlassian,
slack) to auto-allow their everyday writes -- create issue, update issue, add
comment, transition, post message -- while still prompting on the genuinely
destructive operations (deletes, link/watcher removals). The catch: settings
are assembled from a shared `settings.base.json` plus a company
`settings.overlay.json`, merged by `claude-sync` with array
concatenate+dedup semantics. A naive "just add an overlay allow" does not work,
and understanding *why* is the whole lesson.

## Guidance

Two facts determine the design:

1. **Permission precedence is `deny -> ask -> allow`, first match wins, and
   specificity is irrelevant.** Per the Claude Code docs: *"Rules are evaluated
   in order: deny, then ask, then allow. The first match in that order
   determines the outcome, and rule specificity does not change the order."* So
   a matching `ask` rule beats a more specific `allow` rule -- the call still
   prompts.

2. **The overlay merge can only add, never remove.** `claude-sync` deep-merges
   with concat+dedup on string arrays. An overlay can append to
   `permissions.allow`/`ask`/`deny`; it cannot delete a base entry.

Combine them and the consequence is sharp: if the base has a broad
`ask: ["mcp__*__*create*"]`, an overlay `allow: ["mcp__atlassian__*"]` does
**not** silence `jira_create_issue`. The `ask` glob matches first and wins.
An overlay `allow` alone only frees *reads* (which match no `ask` glob).

So to auto-allow a write that matches a broad base `ask` glob, you must
**narrow the base glob** -- there is no overlay-only fix.

### Step 1 -- narrow the base global mutation gate to destructive verbs only

Drop the non-destructive write verbs from the base `permissions.ask`. Keep
only destructive / high-impact verbs.

Before (base `permissions.ask`, mutation-verb globs):

```json
"mcp__*__*create*",
"mcp__*__*delete*",
"mcp__*__*remove*",
"mcp__*__*update*",
"mcp__*__*edit*",
"mcp__*__*add*",
"mcp__*__*transition*",
"mcp__*__*sync*",
"mcp__*__*deploy*",
"mcp__*__*apply*",
"mcp__*__*patch*",
"mcp__*__*write*"
```

After (non-destructive verbs removed; destructive/high-impact retained):

```json
"mcp__*__*delete*",
"mcp__*__*remove*",
"mcp__*__*sync*",
"mcp__*__*deploy*",
"mcp__*__*apply*",
"mcp__*__*patch*",
"mcp__*__*write*"
```

Removing `create`/`update`/`edit`/`add`/`transition` means those verbs no
longer force a prompt on *any* server -- they fall through to the auto-mode
classifier (for servers without an explicit allow) or to an overlay `allow`
(for servers that opt in). The high-impact verbs (`sync`/`deploy`/`apply`/
`patch`/`write`) are kept even though no atlassian/slack tool uses them:
keeping them costs nothing for the goal and preserves caution for future
servers.

### Step 2 -- opt the two servers in via the overlay

The overlay does the server-specific work: a broad `allow` for the two
servers, plus an `ask` list naming the destructive tools by their exact name
(belt-and-suspenders, and self-documenting). Because `ask` outranks `allow`,
those five prompt; everything else under the two servers auto-allows.

`settings.overlay.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__atlassian__*",
      "mcp__slack__*"
    ],
    "ask": [
      "mcp__atlassian__jira_delete_issue",
      "mcp__atlassian__jira_remove_issue_link",
      "mcp__atlassian__jira_remove_watcher",
      "mcp__atlassian__confluence_delete_page",
      "mcp__atlassian__confluence_delete_attachment"
    ]
  }
}
```

Note the syntax asymmetry: an `allow` entry needs a literal, glob-free server
segment (`mcp__atlassian__*` is valid in `allow`). A server-wildcard glob like
`mcp__*__*verb*` is only valid in `ask`/`deny`, not `allow`.

### The fold-merge concept

`claude-sync` folds base + overlays left-to-right. String arrays concatenate
then dedup; objects deep-merge with the overlay winning on scalars:

```jq
def merge(b):
  if (type == "array") and (b | type == "array") then
    if all(type == "string") and (b | all(type == "string"))
    then reduce (. + b)[] as $x ([]; if index($x) then . else . + [$x] end)  # concat + dedup
    else . + b end
  elif (type == "object") and (b | type == "object") then
    reduce (b | to_entries[]) as $e (.;
      if has($e.key) then .[$e.key] |= merge($e.value)
      else . + {($e.key): $e.value} end)                                      # deep merge
  else b end;
```

The merged result is what Claude Code reads. After Step 1 + Step 2, the merged
`permissions.ask` is the narrowed base globs **plus** the five exact-name
atlassian tools; `permissions.allow` gains the two server wildcards. Because
the fold can only add, the base narrowing in Step 1 is load-bearing -- it is
the only thing that removes `create`/`update`/etc. from the gate.

### Verify with a precedence-simulating bash test

Re-run the exact `jq` merge, then resolve representative tools through
`deny -> ask -> allow` with glob matching via `[[ tool == pattern ]]`:

```bash
anymatch() {
  local tool="$1"; shift
  (( $# == 0 )) && return 1          # bash 3.2 + set -u: "${arr[@]}" on an
                                     # empty array is an unbound-variable abort
  local p; for p in "$@"; do [[ "$tool" == $p ]] && return 0; done
  return 1
}
classify() {
  local tool="$1"
  anymatch "$tool" "${DENY[@]}"  && { echo deny;  return; }
  anymatch "$tool" "${ASK[@]}"   && { echo ask;   return; }
  anymatch "$tool" "${ALLOW[@]}" && { echo allow; return; }
  echo classifier
}
```

Assert: reads + non-destructive writes (`jira_create_issue`,
`jira_update_issue`, `jira_transition_issue`, `confluence_create_page`,
`slack_post_message`) resolve to `allow`; the five destructive tools resolve to
`ask`; a hypothetical `mcp__somefuture__create_thing` resolves to `classifier`
(proving the base no longer force-asks `create`) while
`mcp__somefuture__delete_thing` still resolves to `ask`.

## Why This Matters

The intuitive fix -- "add an `allow` for the server in the overlay" -- silently
fails for writes, and the failure is easy to misdiagnose as a typo or a caching
issue. The real cause is structural: `ask` outranks `allow` regardless of
specificity, and a concat-only merge cannot retract the broad base `ask`. Get
this wrong and you either (a) keep getting prompted on every `create`/`update`
despite a "more specific" allow, or (b) over-correct by deleting the whole
mutation gate and lose the destructive-op guardrail for *all* servers. The
narrow-base + opt-in-overlay split keeps the global gate protecting unknown
servers while letting trusted servers run their everyday writes unattended.

## When to Apply

- You run `defaultMode: auto` and want named MCP servers to auto-allow routine
  writes while keeping destructive ones gated.
- Your settings come from a base + overlay assembled by a concat/dedup merge
  (you can add entries but not remove base ones from the overlay).
- You observe a write still prompting despite an overlay `allow` that "should"
  cover it -- check for a broad base `ask` glob matching that verb.
- You are deciding where a guardrail belongs: keep destructive globs in the
  shared base (protect everyone); put server opt-ins in the overlay.

## Examples

Scenario: `jira_create_issue` under `defaultMode: auto`.

Before (broad base `ask` includes `mcp__*__*create*`; overlay adds
`allow: ["mcp__atlassian__*"]`):

```
tool  = mcp__atlassian__jira_create_issue
deny  : (no match)
ask   : mcp__*__*create*   <-- MATCHES, first win  => ask (prompts every time)
allow : mcp__atlassian__*  (never reached)
result: PROMPT  -- the overlay allow is dead weight for this call
```

After (base narrowed -- `create` verb dropped; same overlay):

```
tool  = mcp__atlassian__jira_create_issue
deny  : (no match)
ask   : mcp__*__*delete*, ...destructive..., + 5 exact atlassian deletes  (no match)
allow : mcp__atlassian__*   <-- MATCHES  => allow
result: AUTO-ALLOW  -- no prompt
```

And the guardrail still holds for the destructive sibling:

```
tool  = mcp__atlassian__jira_delete_issue
deny  : (no match)
ask   : mcp__*__*delete*  <-- MATCHES  => ask   (also named explicitly in overlay)
result: PROMPT  -- destructive op still gated
```

## Related

- Claude Code permissions reference:
  https://docs.claude.com/en/docs/claude-code/permissions ("Rules are
  evaluated in order: deny, then ask, then allow ... rule specificity does not
  change the order.")
- `claude/.claude/settings.base.json` -- narrowed `permissions.ask` mutation globs
- `claude/.claude/settings.overlay.json` -- the two-server opt-in (allow + 5 exact-name asks)
- `bin/.local/bin/claude-sync` -- the concat+dedup / deep-merge fold
- `claude/.claude/tests/mcp-permission-overlay/run.sh` -- precedence-simulating verification
- `docs/solutions/conventions/mcp-ask-overrides-destructive-tools-2026-05-25.md`
  -- prior statement of the same "ask beats allow" mechanic, scoped to a single
  destructive tool slipping through a bulk allow. This doc generalizes it and
  adds the base+overlay merge constraint. Note: that doc's examples assume a
  live broad `mcp__*` allow; this repo later dropped the bare allow in favor of
  per-server wildcards + the auto-mode classifier.
- `docs/solutions/developer-experience/claude-settings-permission-rule-warnings-2026-06-12.md`
  -- bare `mcp__*` is invalid in `allow`; only `deny`/`ask` accept the
  server-segment wildcard.
- `docs/solutions/claude-permissions-hardening.md` -- foundational hardening
  doc; its open caveat that the deny/ask/allow precedence was "not
  verbatim-documented" is now resolved by the official-docs quote above.
- Separate MCP failure mode (not precedence-related):
  `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`.
