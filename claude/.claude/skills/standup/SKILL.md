---
name: standup
description: >
  Draft and post a daily virtual standup to #dev-team based on assigned INFRA
  Jira tickets. Composes in Ben's personal writing style.
---

# Virtual Standup

Post your daily standup to the #dev-team Slack channel. Follow these steps in order.

## Step 1 — Query active Jira tickets

Call `mcp__atlassian__atlassian_invoke_tool` with the following arguments:

```json
{
  "tool_name": "jira_search",
  "tool_input": {
    "jql": "project = INFRA AND assignee = currentUser() AND status in ('In Progress', 'QA', 'Ready', 'In Review') ORDER BY updated DESC",
    "fields": "summary,status,updated,issuetype",
    "limit": 20
  }
}
```

## Step 1b — Query To Do tickets (only if Step 1 returns zero results)

If Step 1 returns zero issues, call `mcp__atlassian__atlassian_invoke_tool` to fetch
upcoming work:

```json
{
  "tool_name": "jira_search",
  "tool_input": {
    "jql": "project = INFRA AND assignee = currentUser() AND status = 'To Do' AND priority in (Highest, High) ORDER BY priority DESC, updated DESC",
    "fields": "summary,status,updated,issuetype",
    "limit": 5
  }
}
```

## Step 2 — Query recently completed Jira tickets

Call `mcp__atlassian__atlassian_invoke_tool` with the following arguments:

```json
{
  "tool_name": "jira_search",
  "tool_input": {
    "jql": "project = INFRA AND assignee = currentUser() AND status in ('Done', 'Closed', 'Released') AND updated >= \"-2d\" ORDER BY updated DESC",
    "fields": "summary,status,updated,issuetype",
    "limit": 10
  }
}
```

## Step 3 — Compose the standup

If the combined ticket list from all executed queries is empty (no tickets from
Steps 1, 1b, or 2), stop and report: "No Jira activity found. Please check that the
Jira MCP is connected and that INFRA tickets are assigned to you, then re-run."

Otherwise, write the standup message using the ticket data. Follow these style rules
exactly — they capture Ben's real writing style and must not be deviated from.

**Voice and tone:**
- Opener: exactly `Good morning, team.` — always this phrase, no variation
- Use bullet points for items — 2 to 4 bullets; never more than 4. Each bullet is prefixed with ` •` (space + bullet, not bare `•` or `-`)
- No emoji under any circumstances
- Professional, direct, British English — "organise" not "organize", "colour" not "color", etc.
- Verb patterns (in order of frequency):
  - "I'll be [gerund]…" — dominant future form: "I'll be focusing on…", "I'll be managing…"
  - "I'll also be [gerund]…" — very common for secondary items
  - "I'm continuing [to verb / noun]…" — ongoing work
  - "I'll begin [gerund]…" — new work
  - "Wrapped up [noun]" — completed items, no pronoun
  - "I'm [gerund]…" — current activity: "I'm testing…"
  - "plan to [verb] shortly" — occasional
- Typographic conventions: use smart apostrophes (' U+2019, not ') and em-dashes (— U+2014) for inline elaboration
- Compound sentences are common: main statement followed by clarifying detail after a comma, em-dash, or colon
- Sub-bullets: rare, but when needed use `◦` (U+25E6) indented 4 spaces under the parent bullet
- Completed work first: mention yesterday's finished items before today's plan when relevant
- No sign-off — the standup ends with the last bullet, no "Thanks" or closer
- Explain rationale when relevant (e.g. "progress has been delayed due to higher-priority tasks arising")
- Jira tickets formatted as inline links: `<https://green-energy-trading.atlassian.net/browse/INFRA-XXX|INFRA-XXX>`
- Concise — do not enumerate every ticket, summarise related items where sensible
- If more than 4 distinct workstreams exist, group them thematically into at most 4 bullets

**Ticket mapping:**
- Active tickets (In Progress / QA / Ready / In Review) → describe as today's work
- Recently Done tickets → briefly note completion (e.g. "Wrapped up the certificates deployment earlier this week.")
- Group related tickets in one set of parentheses: `(INFRA-219, INFRA-256)`
- To Do tickets (from Step 1b) → frame as today's plan ("I'll be starting…", "I'll begin…")
- Blockers: mention inline if a ticket's status or summary makes a blocker apparent

**Reference standup — based on Ben's 20 Apr post (adapted to bot format for calibration):**
```
Good morning, team.

 • Yesterday's maintenance was completed successfully. One key benefit is that, following the node group instance type upgrades, we can now utilise more resources at the same cost (INFRA-219, INFRA-256).

 • Thanks to Michael's support, the full Sentry integration is now ready. This will replace UXCam while providing equivalent functionality, including session replay in the Onsite app (INFRA-213).

 • This morning, I'm testing the certificates service with two replicas and plan to deploy it to production shortly (INFRA-221, INFRA-234, INFRA-237).

 • I'll also be organising the INFRA board—closing completed tickets and preparing for the next major initiative: migrating to an Nx monorepo.
```

Note: completed work mentioned first, compound sentences with clarifying detail after
commas and em-dashes, smart apostrophes, grouped ticket references in parentheses,
"I'll also be" pattern, and no sign-off. Match this register exactly.

## Step 4 — Show preview

Display the composed standup message verbatim inside a code block so the user can
review formatting. Then ask: **Post this to #dev-team?**

- If the user replies with any affirmative (yes, post, go ahead, looks good, send it,
  ship it), proceed to Step 5.
- If the user replies with edit, revise, change, or provides corrected text directly,
  ask them for the revised text if not already supplied. Display it in a code block and
  repeat this prompt.
- If the user replies with cancel, no, stop, or abort, confirm cancellation and stop.

## Step 5 — Post to Slack

Once confirmed, call `mcp__slack__slack_invoke_tool` with the following arguments,
substituting the final message text (channel ID is #dev-team):

```json
{
  "tool_name": "slack_post_message",
  "tool_input": {
    "channel_id": "G056E0CUR",
    "text": "<composed standup message>"
  }
}
```

**Message format rules for the `text` field:**
- The `slack_post_message` tool only supports `text` — `blocks` (Block Kit) is not available and will be silently ignored.
- Separate the opener from the first bullet, and each bullet from the next, with a blank line (`\n\n`).
- Each bullet must be prefixed with one space: ` •` (not `•` alone, and not `-`).
- Use smart apostrophes (`'` U+2019) and em-dashes (`—` U+2014) — not straight quotes or hyphens.
- Example structure: `Good morning, team.\n\n • First item.\n\n • Second item.`

If the call returns an error or the response contains no `ts` field, display the full
error response and stop. Do not retry silently.

On success, confirm the post and report the `ts` timestamp returned by Slack.
