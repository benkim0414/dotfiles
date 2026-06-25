# Playwright MCP server for insane-search engine R6/R7 routes

Date: 2026-06-25
Status: approved (brainstorming)

## Problem

The `insane-search@gptaku-plugins` engine fails on DataDome/Turnstile-class
sites (e.g. g2.com) with `ok=False`, `must_invoke_playwright_mcp=TRUE`. The
engine's own failure gates (SKILL.md R6/R7) instruct the agent to drive
MCP Playwright — `browser_navigate` -> `browser_network_requests` -> find an
internal JSON API -> re-fetch via the engine. But no `mcp__playwright__*`
tools are registered, so that route is structurally impossible and the engine
can never get past `NOT EXHAUSTED`.

## Goal

Register a Playwright MCP server so the engine's R6/R7 routes become
executable. "Make g2 work" = unblock the routes the engine cannot run itself,
not guarantee a captcha is solved.

Honest scope: no browser defeats a true DataDome captcha wall on demand. The
realistic win is **R7 reconnaissance** — render the page, capture XHR/fetch
traffic, identify an internal `/api/`·`/graphql`·`.json` endpoint (shallower
WAF than the HTML wall), and re-fetch that endpoint through the engine. If g2
exposes no such endpoint and presents a terminal captcha, the honest result is
a documented terminal block.

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Registration scope | `claude mcp add --scope user` (device-local, `~/.claude.json`) | Matches the existing 4 servers (atlassian/qmd/sequential-thinking/slack); documented in CLAUDE.md prose, not committed |
| Server name | `playwright` | Tools register as `mcp__playwright__*` — the exact names SKILL.md R6/R7 and `engine/executor.py` call |
| Package | `@playwright/mcp@latest` (Microsoft official) | Provides `browser_navigate`, `browser_network_requests`, `browser_snapshot`, `browser_wait_for` |
| Browser | `--browser chrome` (real Chrome channel, headed) | Real Chrome TLS+fingerprint beats bundled Chromium against DataDome; reuses installed Chrome (no Chromium download); headed evades headless heuristics |

## What gets added

```sh
claude mcp add --scope user playwright -- npx @playwright/mcp@latest --browser chrome
```

Writes a `playwright` entry to `~/.claude.json` (device-local). First
invocation fetches the `@playwright/mcp` package via npx and launches the
installed Google Chrome.

## Dependencies

- Node 24 + npx — present (mise).
- Google Chrome.app — present and tracked in `Brewfile` (`cask "google-chrome"`),
  so reproducible across devices.
- No bundled-Chromium download needed (real Chrome channel).

## Routes unlocked (priority order)

1. **R7 recon (primary win):** `browser_navigate` g2 -> `browser_network_requests`
   -> filter `/api/`·`/graphql`·`.json` -> re-fetch JSON via
   `~/.local/share/insane-search/venv/bin/python -m engine <API_URL>`. API
   layer typically has shallower WAF than the HTML wall.
2. **R6 rendered HTML:** `browser_snapshot` for the rendered DOM/accessibility
   tree if Chrome passes the challenge.
3. Satisfies the engine's `must_invoke_playwright_mcp` gate so it stops
   declaring premature failure.

## Verification (acceptance test)

Drive the R7 flow against g2 from the session. Pass =
- g2 content returned via an internal API re-fetch, **OR**
- a documented *terminal* block (true captcha wall, no internal API).

Both are honest outcomes per R6 ("429 ≠ terminal; captcha/auth/404 = terminal").
Also confirm `claude mcp list` shows `playwright: ... - ✔ Connected` and that
`mcp__playwright__*` tools are available in-session.

## Documentation

Add a `playwright` entry to the CLAUDE.md MCP-servers section, in the same
style as the other 4 device-local servers. Note:
- registered via `claude mcp add --scope user playwright -- npx @playwright/mcp@latest --browser chrome`
- purpose: enables insane-search engine R6/R7 routes
- depends on Google Chrome.app (Brewfile cask)

## Out of scope (YAGNI)

- The engine's *other* fallback, local Node `playwright_real_chrome.js`
  (`npm i -g playwright-extra puppeteer-extra-plugin-stealth` +
  `npx playwright install chrome`), is for `needs_real_tls_stack` profiles.
  g2 routes to MCP, not that path. Skip.
- Headless / bundled-Chromium config — weaker evasion, rejected.
- Committed `.mcp.json` — project scope only loads when CWD is the dotfiles
  repo, defeating global use; rejected.
