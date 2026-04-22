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
    "jql": "project = INFRA AND assignee = currentUser() AND status in (\"In Progress\", \"QA\", \"Ready\", \"In Review\") ORDER BY updated DESC",
    "fields": "summary,status,updated,issuetype",
    "limit": 20
  }
}
```

## Step 2 — Query recently completed Jira tickets

Call `mcp__atlassian__atlassian_invoke_tool` with the following arguments:

```json
{
  "tool_name": "jira_search",
  "tool_input": {
    "jql": "project = INFRA AND assignee = currentUser() AND status in (\"Done\", \"Closed\", \"Released\") AND updated >= -2d ORDER BY updated DESC",
    "fields": "summary,status,updated,issuetype",
    "limit": 10
  }
}
```

## Step 3 — Compose the standup

Write the standup message using the ticket data from Steps 1 and 2. Follow these style
rules exactly — they capture Ben's real writing style and must not be deviated from.

**Voice and tone:**
- Opener: exactly `Good morning, team.` — always this phrase, no variation
- Use bullet points (•) for items — 2 to 4 bullets, not more
- No emoji under any circumstances
- Professional, direct, British English — "organise" not "organize", "colour" not "color", etc.
- Action-oriented phrasing: "I'm continuing…", "I'll begin…", "I'll be working on…"
- Explain rationale when relevant (e.g. "progress has been delayed due to higher-priority tasks arising")
- Jira tickets formatted as inline links: `<https://green-energy-trading.atlassian.net/browse/INFRA-XXX|INFRA-XXX>`
- Concise — do not enumerate every ticket, summarise related items where sensible

**Ticket mapping:**
- Active tickets (In Progress / QA / Ready / In Review) → describe as today's work
- Recently Done tickets → briefly note completion (e.g. "Wrapped up INFRA-XXX yesterday.")
- If no active tickets: pick the 1–2 highest-priority To Do items and frame as today's plan ("I'll be starting…")
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

Display the composed standup message verbatim inside a code block so the user can review
formatting. Then ask: **Post this to #dev-team?** Offer three options: post, edit, or cancel.

If the user wants to edit, accept their changes and return to this step.

## Step 5 — Post to Slack

Once confirmed, call `mcp__slack__slack_invoke_tool` with the following arguments,
substituting the composed message:

```json
{
  "tool_name": "slack_post_message",
  "tool_input": {
    "channel_id": "G056E0CUR",
    "text": "<composed standup message>"
  }
}
```

Confirm success and report the timestamp returned by Slack.
