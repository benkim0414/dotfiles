---
name: standup
description: >
  Draft and post your daily virtual standup to #dev-team based on assigned INFRA
  Jira tickets. Composes in Ben's personal writing style. Run each morning before
  posting your update.
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
    "jql": "project = INFRA AND assignee = currentUser() AND status = 'To Do' AND priority in (Highest, High) ORDER BY priority ASC, updated DESC",
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

If all three queries (Steps 1, 1b, and 2) return zero results, stop and report:
"No Jira activity found. Please check that the Jira MCP is connected and that INFRA
tickets are assigned to you, then re-run."

Otherwise, write the standup message using the ticket data. Follow these style rules
exactly — they capture Ben's real writing style and must not be deviated from.

**Voice and tone:**
- Opener: exactly `Good morning, team.` — always this phrase, no variation
- Use bullet points (•) for items — 1 to 4 bullets; never more than 4
- No emoji under any circumstances
- Professional, direct, British English — "organise" not "organize", "colour" not "color", etc.
- Action-oriented phrasing: "I'm continuing…", "I'll begin…", "I'll be working on…"
- Explain rationale when relevant (e.g. "progress has been delayed due to higher-priority tasks arising")
- Jira tickets formatted as inline links: `<https://green-energy-trading.atlassian.net/browse/INFRA-XXX|INFRA-XXX>`
- Concise — do not enumerate every ticket, summarise related items where sensible
- If more than 4 distinct workstreams exist, group them thematically into at most 4 bullets

**Ticket mapping:**
- Active tickets (In Progress / QA / Ready / In Review) → describe as today's work
- Recently Done tickets → briefly note completion (e.g. "Wrapped up INFRA-XXX yesterday.")
- To Do tickets (from Step 1b) → frame as today's plan ("I'll be starting…", "I'll begin…")
- Blockers: mention inline if a ticket's status or summary makes a blocker apparent

**Reference standup — Ben's actual post (for calibration):**
```
Good morning, team.
• I'm continuing to organise the INFRA board. There are several items to address, but progress has been delayed due to higher-priority tasks arising.
• I'll begin migrating the business calendar service to the monorepo this afternoon.
```

Note the natural sentence construction, the explanation of delay, the absence of emoji,
and the forward-looking phrasing. Match this register.

## Step 4 — Show preview

Display the composed standup message verbatim inside a code block so the user can
review formatting. Then ask: **Post this to #dev-team?** Offer three options:
post, edit, or cancel.

If the user wants to edit, ask them to provide their revised text directly. Display
their revised text in a code block and repeat the Post / Edit / Cancel prompt.

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

If the call returns an error or the response contains no `ts` field, display the full
error response and stop. Do not retry silently.

On success, confirm the post and report the `ts` timestamp returned by Slack.
