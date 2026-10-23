# Intent: context-bar mod
Author: Ben Kim. Status: draft.

## Problem

To see where the context window goes you have to run `/context`, which prints
a large grid into the transcript and goes stale on the next turn. The
statusline shows only a total percentage. Nothing persistent shows *what*
fills the window: system prompt, tools, MCP tools, agents, memory files,
skills or messages.

## Proposed outcome

A Claude Code mod draws a live context breakdown as a band above the prompt,
modelled on the context bar in the "Mods in Claude Code" video:

```text
◆ context                                     90k of 1M · compacts at 99%
████▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒░░▒▒····································░
■ system prompt 4.2k 1%  ■ tools 17k 2%  ■ mcp tools 52k 5%  ■ agents 3.4k 1%
■ memory files 8.6k 1%  ■ skills 5.1k 1%  ■ messages 0 0%  ■ free 897k
■ reserved 13k
```

The example adds up: the used categories total 90.3k (the header's `90k`),
and 90.3k used + 897k free + 13k reserved = 1M, the window.

- **Header row:** `◆ context` on the left. On the right is
  `<used> of <window> · compacts at <N>%`, where `<N>` is
  `autoCompactThreshold` as a share of the window. The `compacts at` part is
  left out when auto-compact is off.
- **Bar:** one row as wide as the band, with one segment per `used`
  category in the order `/context` lists them. Each segment is coloured with
  that category's theme colour. Free space follows, and a dim reserved
  segment sits at the right end. `deferred` rows (tool schemas loaded on
  demand) are left out because they sit outside the window.
- **Legend:** wraps across rows. Each entry is a swatch, a lowercase label,
  short tokens (`4.2k`) and a dim percentage. Percentages round to whole
  numbers, and any non-zero share shows at least `1%`, as in the screenshot.
  `free <N>k` comes after the
  used categories. `reserved <N>k` comes last and only appears when the
  buffer is non-zero.
- **Live:** it refreshes at `session.start` (which also runs after a mod
  reload), after each main-loop `turn.complete` (subagent turns are skipped),
  after `session.compact`, and when `/context-bar` turns it on. Each refresh
  stores one reading in `$.state`, and the band redraws from that. It never
  polls.
- **Toggle:** off by default. `/context-bar` turns it on or off. The choice
  is kept in `$.store`, the mod's own JSON file under the user's Claude Code
  configuration directory. That makes it user-wide rather than per project,
  and it survives mod reloads and restarts. While the band is off, the mod
  makes no `usage()` calls.

### Accounting: used, free and reserved

The window is the breakdown's `rawMaxTokens`. Every figure in the band is a
share of that one denominator.

- **used:** the `used` categories. Their sum is the header's `<used>`
  (`totalTokens`).
- **free:** the `free` row's tokens, taken from the API as they are. The mod
  never computes free as window minus used, because that would silently
  include the reservation.
- **reserved:** the `buffer` row, which is the compaction reserve. It is
  drawn as the dim tail segment and listed as `reserved`. With auto-compact
  off there is no buffer row, so there is no reserved segment or entry, and
  free fills the rest.
- **Reconciliation:** header, bar and legend must agree, whether
  auto-compact is on or off. used + free + reserved = window, give or take
  the rounding of short tokens. The bar gives each part
  `round(tokens / window × width)` cells, with at least one cell for any
  non-zero category. Any rounding surplus or shortfall is absorbed by the
  free segment, so the bar is always exactly `width` cells.
- **Over the window:** when used passes the window, free and reserved show
  0, the bar is all used, and the header keeps the true figure
  (`1.02M of 1M`).

### Unavailable or failed refresh

- If `usage()` rejects, returns no `breakdown`, or returns one with no
  `used` rows, the mod clears its stored reading. The band then steps aside
  (`next(e)`) instead of showing stale numbers.
- A compaction clears the reading before the refresh after it, so
  pre-compaction usage is never shown as live.
- The next successful refresh brings the band back. No retry loop or timer
  is involved.
- Failures are contained. The event hook catches the error, logs one debug
  line, and always returns `next(e)`. The prompt, the turn and compaction
  are never delayed or blocked by the mod.

### Width

The band's width is `e.props.bodyColumns`. No layout may overflow
horizontally; any text that would not fit is truncated with `…`.

| Columns | Shows |
| --- | --- |
| 60 and up | header, bar, legend |
| 40–59 | header with the right part shortened to `90k/1M · 99%`; bar; no legend |
| 20–39 | one row: `◆ 90k/1M` followed by the bar in the remaining columns |
| under 20 | nothing (the band steps aside) |

## Affected users and systems

- **The person at the prompt:** sees what fills the window without running
  `/context`.
- **Claude Code:** a `ui.render` hook on `{ component: 'AbovePrompt' }`. It
  steps aside (`next(e)`) while a survey shows (`e.props.hasSurvey`), while
  toggled off, when there is no valid reading, and below 20 columns. It
  draws through `$.ui.resolve(e)`, so it works on any surface; the terminal
  is the primary target. `/context-bar` is registered with
  `$.command.register` in `session.start` and answered by a `command.run`
  hook.
- **The model:** unaffected. The mod is display only and never touches the
  prompt or the transcript.

## Constraints

- **Data source:** `$.session.usage({ breakdown: 'summary' })`. It returns
  `context.breakdown` with `categories[]` (`name`, `tokens`, theme `color`,
  and `kind`, which is one of `used`/`free`/`buffer`/`deferred`),
  `totalTokens`, `rawMaxTokens`, `autoCompactThreshold` and
  `isAutoCompactEnabled`. These are the same rows `/context` prints. The mod
  branches on `kind`, never on a row's `name`.
- **Summary counting:** a local estimate with no token-count API calls per
  refresh. `full` counting is a later option.
- **Never blocks drawing:** `usage()` runs in event hooks and stores its
  reading in `$.state`. The render hook only reads that state.
- **No npm dependencies**, unlike mermaid-ascii's converter.
- **Lives in dotfiles:** it ships in the `claude` Stow package under
  `claude/.claude/mods/context-bar/` and loads through
  `CLAUDE_CODE_PLUGIN_DIRS` in `claude/.claude/settings.json`, like
  mermaid-ascii.

## Open questions

- How to map labels from `/context` names to the short legend labels, for
  example `System tools` → `tools`, `Custom agents` → `agents`. Names are
  used only for the label; unknown names fall back to the lowercased name.
- Should `/context-bar` take `on|off` arguments, or only toggle?
- How the bar draws partial cells, given the screenshot's smooth segments
  (eighth-block glyphs, or whole cells only).
- Whether the video's bar hides the reservation. The screenshot shows no
  reserved segment, yet its figures leave about 13k of the 1M window
  unaccounted for, which fits a buffer. This intent shows the reservation so
  the figures reconcile.

## Later changes (each gets its own intent)

- A `full` counting option (`userConfig`) for exact counts from the
  token-count API.
- Expanding a segment to list its items: memory files, MCP servers and their
  tools, agents, skills.
- Showing the band automatically once usage passes a threshold.
- A per-project toggle, if the user-wide one proves too coarse.

## Background

- Video: [Mods in Claude Code: change how Claude Code works](https://www.youtube.com/watch?v=yUuFvL1lK4k)
  (Claude channel, 2026-10-05). Its description lists "a live context
  breakdown" as one of three demo mods. The transcript could not be fetched
  and the mod's code is not published, so a screenshot of it is the visual
  spec.
- [Getting started with Claude Code mods](https://claude.dev/blog/getting-started-with-claude-code-mods/):
  Token Weather is the nearest published example (an `AbovePrompt` band fed
  by `$.session.usage()`). Code:
  [claude-code-playground/claude-code/mods](https://github.com/anthropics/claude-code-playground/tree/main/claude-code/mods).
- Mod API types (`claude-code.d.ts`, written by the plugin-authoring skill;
  checked against build 2.1.309): `$.session.usage`, `SessionUsageArgs`,
  `SessionContextBreakdown`, `ContextCategory`, `ContextCategoryKind`,
  `$.store`.
- The existing statusline: `claude/.claude/statusline.sh`.
