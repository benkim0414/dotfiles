---
title: Playwright MCP server for insane-search WAF escalation (real Chrome channel)
date: 2026-06-25
category: tooling-decisions
module: insane-search
problem_type: tooling_decision
component: tooling
severity: medium
related_components:
  - development_workflow
applies_when:
  - insane-search engine must escalate a DataDome/Turnstile-class WAF site to MCP Playwright
  - "registering the Playwright MCP server so tools resolve as mcp__playwright__* for the engine SKILL.md R6/R7 routes"
  - choosing between real Chrome channel and bundled headless Chromium for anti-bot fingerprinting
  - a target server-renders HTML and exposes no internal JSON API (browser_snapshot rendered-DOM route, not API-recon)
tags:
  - playwright
  - mcp
  - insane-search
  - datadome
  - turnstile
  - waf-bypass
  - google-chrome
  - browser-automation
  - dotfiles
---

# Playwright MCP server for insane-search WAF escalation (real Chrome channel)

## Context

The `insane-search` plugin engine ends its fetch-method grid with an explicit escalation hook: when every cheaper method (curl_cffi TLS impersonation, mobile URL transforms, Jina Reader, public APIs) has exhausted against a WAF-protected site, the engine emits `must_invoke_playwright_mcp=TRUE`. That flag is the engine telling the agent: "I cannot get past this bot wall with HTTP alone — escalate to a real browser."

The friction: the flag fired, but there were no `mcp__playwright__*` tools registered in the harness. The engine's SKILL.md R6 (rendered-DOM) and R7 (API-recon) routes both invoke specific Playwright MCP tools by name — `browser_navigate`, `browser_network_requests`, `browser_snapshot`, `browser_wait_for`. With no Playwright MCP server present, those routes were not merely unused; they were *structurally impossible*. The engine could detect that it needed a browser, point at exactly which tools to call, and then dead-end because the tools did not exist. The escalation path was a promise the harness could not keep.

## Guidance

Register a Playwright MCP server, device-local, with a precise name and a real-Chrome browser channel.

```sh
claude mcp add --scope user playwright -- npx @playwright/mcp@latest --browser chrome
```

Three choices in that command are load-bearing:

**Server name MUST be `playwright`.** The MCP tool namespace is derived from the server name: name `playwright` produces `mcp__playwright__browser_navigate`, `mcp__playwright__browser_network_requests`, `mcp__playwright__browser_snapshot`, `mcp__playwright__browser_wait_for` — the exact identifiers the engine's SKILL.md R6/R7 rules call. Any other server name (e.g. `pw`, `browser`, `playwright-mcp`) produces a different prefix, and the engine's escalation silently breaks: the flag still fires, the agent still reads "invoke `mcp__playwright__browser_navigate`", and the call fails because that tool does not exist under that name. The name is a contract with the engine, not a free label.

**`--browser chrome` (real Google Chrome channel, headed), not headless or bundled Chromium.** Three reasons:
- *Bot-detection evasion.* Real Chrome's TLS handshake and browser fingerprint beat DataDome-class detection that flags bundled Chromium and headless signatures. Headed operation evades the headless-mode heuristics (missing `navigator.webdriver` quirks, renderer timing) that WAFs probe for.
- *No extra binary.* The `--browser chrome` channel reuses the Google Chrome already installed via the Brewfile cask `google-chrome`. There is no separate Chromium download to manage or keep current.
- *Honest fingerprint.* A real user's browser is the strongest possible fingerprint precisely because it is not a simulation.

**Device-local (`~/.claude.json`), not committed.** This matches the repo's existing convention for its four other MCP servers (atlassian, qmd, sequential-thinking, slack), which all live in the device-local config rather than tracked dotfiles. Re-run the `claude mcp add` command once per device. Verify registration with:

```sh
claude mcp list
# expect: playwright  ✔ Connected
```

**Session reload caveat.** `claude mcp add` writes the registration immediately, but a *running* Claude Code session does not see the new `mcp__playwright__*` tools until the MCP layer reloads. After adding, run `/mcp` to reload (or restart the session). Skipping this step is the most common "I added it but the tools still aren't there" failure — the registration is correct; the running process just hasn't re-read it.

**Engine venv invocation (related dependency gotcha).** The engine's Python dependencies — notably `curl_cffi` — live in a uv-managed venv at `~/.local/share/insane-search/venv` (Python 3.12). Homebrew's Python 3.14 is PEP-668 externally-managed and has no `curl_cffi` wheels for 3.14, so a bare `python3 -m engine` fails with `curl_cffi not installed`. SKILL.md hardcodes bare `python3`, which is wrong for this setup. Always invoke the engine through the venv interpreter:

```sh
~/.local/share/insane-search/venv/bin/python -m engine "<URL>"
```

## Why This Matters

Get any of the three knobs wrong and the failure is quiet, not loud:

- **Wrong server name** → the engine's R6/R7 escalation points at `mcp__playwright__*` tools that don't exist under your chosen prefix. The flag fires, the route is named, and the call dead-ends. Nothing crashes; the bypass just never happens.
- **Wrong browser (headless/bundled Chromium)** → you get a browser that the WAF detects on sight. You've added complexity and a binary download and still lose to DataDome — arguably worse than not having Playwright, because it *looks* like you have an escalation path.
- **Wrong Python (bare `python3`)** → the engine fails before it even reaches the Playwright escalation, with a `curl_cffi not installed` error that looks like a Playwright problem but isn't.

Honest framing on what a browser does and does not buy you: **no browser defeats a true captcha wall on demand.** If a site throws an interactive captcha that requires solving, a real headed Chrome gets you to the captcha — it does not solve it. The win Playwright delivers is *recon and render*: passing passive bot-detection (TLS/fingerprint/headless heuristics) to either read an internal API (R7) or capture the rendered DOM (R6). When a site escalates to a terminal captcha that even a real browser can't pass unattended, **terminal captcha is an honest outcome** — report it as the wall it is, don't pretend a tool can brute past it.

## When to Apply

Apply this when the `insane-search` engine grid exhausts against a WAF-protected site and flags `must_invoke_playwright_mcp=TRUE`. That flag is the trigger; do not reach for Playwright before the cheaper HTTP methods have been tried, because the browser is the heaviest and slowest method in the grid.

Once you're in Playwright, choose the route by how the site renders:

- **Server-rendered site → R6 (rendered-DOM snapshot).** If the HTML arrives fully populated from the server, the content you want is already in the DOM after navigation. `browser_snapshot` returns it directly. There is no internal JSON API to recon because the server did the rendering.
- **SPA / JSON-API site → R7 (API-recon, the intended primary route).** If the page is a client-side app that fetches its data from internal endpoints, navigate, capture network traffic with `browser_network_requests`, find the internal `/api`, `/graphql`, or `.json` endpoint, then re-fetch *that endpoint* through the engine. The API layer typically sits behind a shallower WAF than the HTML wall, so once you know the endpoint URL the engine's cheap HTTP methods often succeed against it directly.

R7 is the *intended primary* route because re-fetching a discovered endpoint is cheaper and more robust than scraping rendered DOM. R6 is the fallback. But the verified g2 case (below) shows the inverse can hold: for server-rendered sites there is no API to recon, and R6 wins outright.

## Examples

**Verified walkthrough — g2.com (2026-06-25), DataDome-protected.**

g2.com sits behind DataDome. The engine grid exhausted and flagged `must_invoke_playwright_mcp=TRUE`. With the `playwright` server registered (`--browser chrome`, headed), the escalation ran:

1. **Navigate** with real Chrome:
   ```
   mcp__playwright__browser_navigate(url: "https://www.g2.com/...")
   ```
   Real Chrome's TLS + fingerprint passed DataDome — no block page, no captcha.

2. **Wait** for the page to settle:
   ```
   mcp__playwright__browser_wait_for(...)
   ```

3. **Capture network** to test for an R7 API-recon opportunity:
   ```
   mcp__playwright__browser_network_requests()
   ```
   The capture showed *only* cookie-consent and animation JSON — no internal `/api`, `/graphql`, or data `.json` endpoint. g2 server-renders its HTML, so **R7 was N/A**: there was no shallower API layer to discover and re-fetch.

4. **Snapshot** the rendered DOM:
   ```
   mcp__playwright__browser_snapshot()
   ```
   Returned the full real page content. **R6 was the winning route.**

**Outcome and lesson.** Real Chrome passed DataDome and the full page rendered. The R6 rendered-DOM snapshot was the winning route; R7 was not applicable because g2 exposes no internal JSON API. The general lesson: **for server-rendered sites behind a WAF, the rendered-DOM snapshot (R6) beats API-recon — R7 only wins for SPA / JSON-API sites.** The "R7 primary, R6 fallback" priority in SKILL.md is a default that inverts the moment network capture reveals there's no API to recon.

**Engine invocation used throughout** (note the venv interpreter, not bare `python3`):

```sh
~/.local/share/insane-search/venv/bin/python -m engine "https://www.g2.com/..."
```

## Related

- `docs/solutions/tooling-decisions/reproducible-claude-plugins-via-extraknownmarketplaces-2026-06-25.md` — closest sibling. Makes the insane-search *plugin* reproducible across devices (`enabledPlugins` + `extraKnownMarketplaces`); this doc adds the Playwright MCP *server* the same plugin's engine escalates to. Distinct problem, shared `settings.base.json` context.
- `docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md` — MCP-server-setup lineage; establishes the `claude mcp add --scope user` convention this server follows (and why the other four servers run raw).
- `docs/solutions/tooling-decisions/claude-code-permission-deny-ask-allow-precedence-2026-06-18.md` — the permission posture (`defaultMode: auto` + classifier; `mcp__*` allow/ask rules) the new `mcp__playwright__*` tools inherit.
- Auto-memory `reference-insane-search-venv` (`~/.claude/projects/.../memory/reference_insane_search_venv.md`) — the engine's pinned-3.12 venv and its R6/R7 failure gates (g2 DataDome / Reddit 429), verified same session.
