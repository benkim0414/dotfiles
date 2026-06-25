# Playwright MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register `@playwright/mcp` as a user-scope MCP server named `playwright` so the insane-search engine's R6/R7 routes (`mcp__playwright__*` tools) become executable, then verify against g2.com and document it.

**Architecture:** Device-local registration via `claude mcp add --scope user` (writes `~/.claude.json`, matching the existing 4 servers). Real Chrome channel, headed, for bot-detection evasion. The only committed artifact is a CLAUDE.md documentation entry — the server config itself is device-local and not version-controlled, same as the other 4 servers. Verification drives the engine's R7 reconnaissance flow against g2.

**Tech Stack:** Claude Code MCP, `@playwright/mcp@latest` (Microsoft official), Google Chrome (channel), Node 24 (mise), insane-search engine (venv python at `~/.local/share/insane-search/venv`).

---

## File Structure

- **Modify:** `CLAUDE.md` — add a `playwright` entry to the MCP-servers documentation section.
- **Runtime only (not committed):** `~/.claude.json` — gains a `playwright` MCP server entry via `claude mcp add`.

No source code changes. No test files (infra + docs task; the g2 R7 flow is the acceptance test).

---

### Task 1: Register the Playwright MCP server

**Files:**
- Runtime: `~/.claude.json` (via `claude mcp add` — do NOT hand-edit)

- [ ] **Step 1: Add the server (user scope, real Chrome channel)**

```bash
claude mcp add --scope user playwright -- npx @playwright/mcp@latest --browser chrome
```

Expected output: a confirmation line such as `Added MCP server playwright ... to user config`.

- [ ] **Step 2: Confirm it is registered and connects**

```bash
claude mcp list 2>&1 | grep -i playwright
```

Expected: a line `playwright: npx @playwright/mcp@latest --browser chrome - ✔ Connected`.
If it shows a failure instead of `✔ Connected`, the first `npx` fetch of `@playwright/mcp` may still be downloading — wait and re-run. A persistent failure means Chrome could not launch (verify `ls -d "/Applications/Google Chrome.app"`).

- [ ] **Step 3: No commit**

`~/.claude.json` is device-local and gitignored-by-convention (never committed, like the other 4 servers). Nothing to commit in this task.

---

### Task 2: Verify the `mcp__playwright__*` tools are available in-session

**Files:** none (session capability check)

- [ ] **Step 1: Reload MCP so the new server's tools register in this session**

The newly added server's tools are not live in an already-running session until reloaded. Run the `/mcp` reload (or restart the session). After reload, the deferred tool list should include `mcp__playwright__browser_navigate`, `mcp__playwright__browser_network_requests`, `mcp__playwright__browser_snapshot`, `mcp__playwright__browser_wait_for`.

- [ ] **Step 2: Confirm tool availability**

Load the schemas to confirm they resolve:

```
ToolSearch query: select:mcp__playwright__browser_navigate,mcp__playwright__browser_network_requests
```

Expected: `Tool loaded.` (no `unknown tool` error). This proves the server name `playwright` produced the `mcp__playwright__*` prefix the engine expects.

---

### Task 3: Acceptance test — drive the engine R7 flow against g2

**Files:** none (live verification; honest pass/fail per spec)

- [ ] **Step 1: Render g2 in the MCP browser**

Call `mcp__playwright__browser_navigate` with `url: "https://www.g2.com/categories/crm"`. Then `mcp__playwright__browser_wait_for` (short, e.g. `time: 3`) to let any challenge script settle.

- [ ] **Step 2: Capture network traffic and find an internal API**

Call `mcp__playwright__browser_network_requests`. Scan the returned request list for internal data endpoints matching `/api/`, `/graphql`, or `.json` (NOT static assets, analytics, or the DataDome `captcha-delivery.com` calls).

- [ ] **Step 3: Branch on what was found**

- **If an internal JSON/API endpoint exists:** re-fetch it through the engine (API layer = shallower WAF):

```bash
cd "/Users/ben/.claude/plugins/cache/gptaku-plugins/insane-search/0.8.2/skills/insane-search"
~/.local/share/insane-search/venv/bin/python -m engine "<API_URL_FROM_STEP_2>" 2>&1 | tail -6
```

Expected: `ok=True` with JSON content, OR a clear status to iterate on (e.g. needs a query param).

- **If no internal API and the page rendered past the challenge:** call `mcp__playwright__browser_snapshot` and confirm it returns g2 category content (not the `Please enable JS` / captcha interstitial).

- **If only the DataDome captcha interstitial renders and no internal API appears:** this is a *terminal* block. Record it honestly — adding the server was still correct (it made the route executable); g2 specifically is captcha-walled.

- [ ] **Step 4: Record the outcome**

The acceptance test passes if EITHER g2 content was retrieved (via API re-fetch or snapshot) OR a terminal captcha block was demonstrated and documented. Both are honest results per spec (R6: captcha = terminal, 429 = not terminal). Note the actual outcome for the CLAUDE.md entry in Task 4.

---

### Task 4: Document the server in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (project root, MCP-servers documentation area)

- [ ] **Step 1: Locate the MCP-servers section**

Run:

```bash
grep -n "Brewfile rules\|MCP server" CLAUDE.md | head
```

The new subsection goes under the "Secrets"/"Wiki staging" infra documentation, before "Stow gotchas" — a top-level `# MCP servers` section. (The detailed permission posture for the global `~/.claude` servers lives in the personal `claude/.claude/CLAUDE.md`, not this project file; this entry is a short project-level note that the dotfiles repo's insane-search workflow depends on it.)

- [ ] **Step 2: Add the documentation block**

Insert this section (exact content):

```markdown
# MCP servers (Playwright)

The `insane-search` plugin's engine escalates DataDome/Turnstile-class sites to
MCP Playwright (its R6/R7 routes call `mcp__playwright__*` tools). Register the
server device-local (user scope), matching the convention for the other MCP
servers in `~/.claude.json`:

```sh
claude mcp add --scope user playwright -- npx @playwright/mcp@latest --browser chrome
```

- Server name MUST be `playwright` so tools register as `mcp__playwright__*`
  (the names the engine and SKILL.md R6/R7 call).
- `--browser chrome` uses the installed Google Chrome channel (Brewfile cask
  `google-chrome`) — stronger bot-detection evasion than bundled Chromium, and
  no extra browser binary to download.
- Device-local (`~/.claude.json`), not committed — re-run the command on each
  device. Verify with `claude mcp list` (expect `✔ Connected`).
- insane-search engine deps run from `~/.local/share/insane-search/venv`; the
  engine re-fetches any internal API found via Playwright network capture.
```

- [ ] **Step 3: Verify the edit**

```bash
grep -n "MCP servers (Playwright)" CLAUDE.md
```

Expected: one matching line.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): document playwright mcp server for insane-search"
```

---

## Self-Review

**Spec coverage:**
- Registration scope (user-scope) → Task 1. ✓
- Server name `playwright` → Task 1 + verified Task 2. ✓
- Package `@playwright/mcp` + `--browser chrome` → Task 1. ✓
- Routes unlocked (R7 recon, R6 snapshot, gate satisfaction) → Task 3. ✓
- Verification (g2 R7 flow + `claude mcp list` connected + tools available) → Tasks 1–3. ✓
- Documentation in CLAUDE.md → Task 4. ✓
- Out of scope (local node real-chrome, headless, committed .mcp.json) → not implemented, correct. ✓

**Placeholder scan:** `<API_URL_FROM_STEP_2>` in Task 3 is a runtime-discovered value, not a plan placeholder — it cannot be known until the network capture runs, and the step explains exactly how to obtain it. No other placeholders.

**Type consistency:** Tool names used consistently — `mcp__playwright__browser_navigate`, `browser_network_requests`, `browser_snapshot`, `browser_wait_for`. Engine invocation path consistent with the saved memory: `~/.local/share/insane-search/venv/bin/python -m engine`. Server name `playwright` consistent across all tasks.
