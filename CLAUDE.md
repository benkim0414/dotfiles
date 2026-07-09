# Dotfiles

macOS/Linux dotfiles managed with GNU Stow and Homebrew.

# Commands

Documented solutions: `docs/solutions/` stores past fixes and decisions by category with YAML frontmatter (`module`, `tags`, `problem_type`); relevant when implementing or debugging in documented areas.

## Daily workflow

```sh
stow -t ~ <package>          # symlink a package into ~
stow -t ~ -D <package>       # remove a package's symlinks
stow -t ~ -R <package>       # re-stow after restructuring
```

## Adding a new tool

1. Add to Brewfile (`brew` for CLI, `cask` for GUI apps)
2. Create package dir mirroring home layout: `<pkg>/.config/<tool>/...`
3. `stow -t ~ <pkg>`

# Secrets

Bitwarden via mise: `mise-load-bw` resolves `.env.bw` (`VAR=uuid:field` format) into
a cached `.env.local` file. Load it with `[env] _.file = [".env.local"]` in `.mise.toml`
and add a task: `[tasks.secrets] run = "mise-load-bw"`. Run `mise run secrets` after
first clone or secret rotation. 1Password: same pattern with `mise-load-op` and `.env.op`.
Never use `_.source` for secret scripts -- mise re-runs them on every prompt.
Never commit `.env*` or `.mise.local.toml` files -- they are gitignored.

# Wiki staging

Generated plugin docs (`docs/superpowers/{specs,plans}/`, `docs/solutions/`) are
mirrored into `~/workspace/wiki/raw/<repo>/` for later `/ingest` into the wiki's
`okf/` knowledge pages.

- `wiki-stage` -- idempotent mirror of a repo's tracked `docs/` tree into
  `~/workspace/wiki/raw/<repo>/`. Content-hash skip, never deletes, exits 0 on
  every guard. Safe to run manually anytime (also backfills).
- `wiki-stage-install` -- installs a `post-merge` hook into a repo so staging
  fires automatically when docs merge to `main`. Run once per repo to wire it;
  refuses to clobber an existing foreign hook. Husky-aware: in repos that set
  `core.hooksPath` it installs at `.husky/post-merge` (kept local via
  `.git/info/exclude`), since git ignores `.git/hooks/` there.
- Staging is copy-only: it never commits or pushes the wiki. Ingestion into
  `okf/` stays a separate manual step (the wiki's `/ingest` skill).

Design: `docs/superpowers/specs/2026-06-22-wiki-stage-docs-mirror-design.md`.

# Documented solutions

`docs/solutions/` holds documented solutions to past problems (bugs, conventions,
workflow patterns), organized by category with YAML frontmatter (`module`, `tags`,
`problem_type`). Relevant when implementing or debugging in a documented area.

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
  `google-chrome`) -- stronger bot-detection evasion than bundled Chromium, and
  no extra browser binary to download.
- Device-local (`~/.claude.json`), not committed -- re-run the command on each
  device. Verify with `claude mcp list` (expect `✔ Connected`).
- insane-search engine deps run from `~/.local/share/insane-search/venv`; the
  engine re-fetches any internal API found via Playwright network capture.
- Verified 2026-06-25: headed real Chrome passed g2's DataDome challenge and
  rendered the full page via `browser_snapshot` (the R6 rendered-DOM route).
  g2 server-renders its HTML and exposes no internal JSON API, so the R7
  API-recon route was N/A -- snapshot is the winning route for that class of site.

Design: `docs/superpowers/specs/2026-06-25-playwright-mcp-design.md`.

# herdr

herdr (homebrew-core `brew "herdr"`) is the primary agent workspace manager. The
`herdr/` Stow package ships a minimal `~/.config/herdr/config.toml` that remaps
herdr's keymap onto tmux muscle memory: prefix `ctrl+s`, `prefix s` = stacked
split, `prefix v` = side-by-side split, `settings` moved to `prefix ,`. `r`
(resize), `R` (reload), `b` (sidebar) stay at herdr defaults.

In navigate mode the workspace sidebar list moves with `j`/`k`
(`navigate_workspace_up/down`); the up/down arrows are reassigned to pane
vertical focus (`navigate_pane_up/down`). Pane nav elsewhere is unchanged
(`ctrl+hjkl`, `prefix+hjkl`).

New panes explicitly launch zsh as a login shell so the stowed zsh config and
Starship prompt load even when the Herdr server was started from a sparse
environment.

Direct `ctrl+h/j/k/l` pane navigation comes from the `vim-herdr-navigation`
herdr plugin (a vim-tmux-navigator port): it forwards the key into vim when a
vim/neovim pane is focused, else moves herdr focus, and falls back to tmux or
`wincmd` outside herdr. The nvim side is folded into the `vim-tmux-navigator`
spec in `nvim/.config/nvim/lua/plugins/nav.lua`.

`config.toml` is direct-stowed: herdr only writes the `onboarding` flag and never
rewrites keys at runtime (runtime state lives in separate files -- `session.json`,
sockets, `*.log`). No base+generated pattern is needed (unlike codex).

Per-device setup (one time):

1. `brew bundle --file=Brewfile` -- installs herdr.
2. `herdr plugin install paulbkim-dev/vim-herdr-navigation --yes` -- registers the
   `vim-herdr-navigation.*` actions the config's `ctrl+hjkl` binds call. If
   lazy.nvim has already cloned the repo, `herdr plugin link
   ~/.local/share/nvim/lazy/vim-herdr-navigation` is also valid for this machine.
   herdr plugins live in herdr's own store, not Stow-managed (like `tpm` for tmux).
3. `rm -f ~/.config/herdr/config.toml` (removes herdr's auto-created stub) then
   `stow -t ~ herdr`.
4. Launch nvim once so lazy.nvim syncs `vim-herdr-navigation`.
5. `herdr server reload-config` (or restart the server) to load the keys.

Design: `docs/superpowers/specs/2026-07-09-herdr-tmux-keybindings-design.md`.

# Stow gotchas

- **Always pass `-t ~`**. There is no .stowrc; the default target is the parent dir (`~/workspace/`), not `~`.
- **Before stowing `bin`**: run `mkdir -p ~/.local/bin` first. Otherwise Stow tree-folds and creates a directory symlink, which breaks other tools that install into `~/.local/bin`.
- **Before stowing `codex`**: run `mkdir -p ~/.codex` first, then `codex-sync`. Same tree-folding issue -- Codex writes runtime state (history, logs) into `~/.codex/`.
- **Before stowing `herdr`**: herdr auto-creates `~/.config/herdr/config.toml` (an `onboarding` stub) on first run. Remove it (`rm -f ~/.config/herdr/config.toml`) before `stow -t ~ herdr`, or Stow refuses to overlay the non-symlink target.
- **Stow refuses absolute symlinks**. Files installed by external tools (claude, git-filter-repo, uv, uvx) must NOT be added to the bin package -- leave them as-is in `~/.local/bin`.
- **After restructuring a package dir**, use `stow -t ~ -R <package>` to clean up stale symlinks.

# Package conventions

- Each top-level directory is a Stow package mirroring the home directory layout.
- Config files are edited in-place in the package dir; symlinks make changes live immediately.
- Custom scripts go in `bin/.local/bin/` and must be executable.
- The `claude/` package stows to `~/.claude/` (hooks, rules, plugins, and project instructions). `settings.json` is generated by `claude-sync` -- not stowed directly. PR mechanics go through `compound-engineering:ce-commit-push-pr` and `ce-resolve-pr-feedback`; the local `pr/` plugin was extracted to `benkim0414/skills` in commit `58762e3` and the `pr@skills` external replacement is no longer declared in `settings.base.json`.
- The `codex/` package stows a minimal global `~/.codex/config.toml`. Stable Codex settings live in `codex/.codex/config.base.toml`; run `codex-sync` to regenerate the gitignored `config.toml` before stowing or after editing the base config. Codex writes UI notices, plugin state, and local project trust entries into `config.toml`, so that generated file is intentionally ignored.

# Claude Code settings (layered merge)

Base settings live in `claude/.claude/settings.base.json`. A single
overlay is folded on top (later wins on scalar conflict):

1. `claude/.claude/settings.overlay.json` -- company overlay, committed
   to this repo (e.g. atlassian/slack MCP auto-allow). Always applies.

Run `claude-sync` after editing either of them to regenerate
`~/.claude/settings.json`. The script deep-merges arrays (concatenate +
deduplicate) and objects (overlay wins). With no overlay present it
copies the base as-is.

The `~/workspace/claude-skills/settings.overlay.json` overlay was detached
on 2026-06-30: it carried stale broad `ask` globs
(`create/update/edit/add/transition/invoke`) that re-gated Atlassian
non-destructive MCP tools. Because `ask` beats `allow` and the merge only
concatenates (it cannot subtract), the company `mcp__atlassian__*` allow
could not suppress them. Base + company overlay are now the sole authority
for MCP verb gating.

## Plugins and marketplaces (cross-device)

Two `settings.base.json` keys make the plugin set reproducible on any
device through synced settings alone -- no manual `/plugin marketplace
add`:

- `enabledPlugins` toggles each plugin on (`"plugin@marketplace": true`).
- `extraKnownMarketplaces` declares the marketplace each plugin comes
  from (`github` source + `repo`). On a fresh device Claude Code
  auto-installs every declared marketplace after a one-time trust
  prompt. Every entry sets `"autoUpdate": true`, so Claude Code refreshes
  the marketplace and updates its installed plugins at startup.

A plugin needs an `enabledPlugins` entry AND -- unless it lives on the
official Anthropic marketplace -- an `extraKnownMarketplaces` entry for
its marketplace. `claude-md-management@claude-plugins-official` rides the
auto-known official marketplace, so it has no `extraKnownMarketplaces`
entry by design. Both keys are objects, so `claude-sync` deep-merges
them (overlay wins); they live in the base, not an overlay, because they
are personal cross-device config.

Instructions layer separately from settings: `claude/.claude/CLAUDE.md` holds
personal defaults and imports company-wide instructions via
`@CLAUDE.company.md` (a native Claude Code import, resolved relative to the
stowed `~/.claude/CLAUDE.md`). `claude-sync` does not touch CLAUDE.md -- the
import is resolved by Claude Code at load time.

## Permission posture

User-scope defaults (in `claude/.claude/settings.base.json`):

- `defaultMode: "auto"` -- new sessions open in auto mode. A classifier
  judges unmatched tool calls; explicit `allow` entries skip the
  classifier. Requires Opus 4.6+ / Sonnet 4.6+ (Opus 4.7 in use).
- Most MCP tools are not pre-approved in `allow` (bare `mcp__*` is
  invalid there -- only `deny`/`ask` accept bare wildcards). Under
  `defaultMode: "auto"` the classifier judges each unmatched MCP call.
  The exception is context-mode: the nine non-destructive context-mode
  tools (`ctx_batch_execute`, `ctx_doctor`, `ctx_execute`,
  `ctx_execute_file`, `ctx_fetch_and_index`, `ctx_index`, `ctx_insight`,
  `ctx_search`, `ctx_stats`) are listed by exact name in `allow` so they
  skip the classifier and never prompt; `ctx_purge` and `ctx_upgrade`
  stay in `ask`.
- `ask` rules gate destructive + high-impact MCP mutations: the
  `mcp__*__*delete*`, `*remove*`, `*sync*`, `*deploy*`, `*apply*`,
  `*patch*`, `*write*` globs (the `mcp__*__` server-segment wildcard is
  valid only in `ask`/`deny` -- `allow` requires a literal, glob-free
  server segment, so do not move these to `allow`), plus two destructive
  context-mode tools --
  `mcp__plugin_context-mode_context-mode__ctx_purge` (wipes the FTS5
  knowledge base, irreversible) and
  `mcp__plugin_context-mode_context-mode__ctx_upgrade` (pulls, builds,
  and installs from GitHub). The non-destructive write verbs
  (`create`/`update`/`edit`/`add`/`transition`) are intentionally NOT
  globally gated -- under `defaultMode: auto` they fall to the
  classifier, and the company overlay auto-allows them for atlassian and
  slack.
- atlassian + slack MCP posture (company overlay,
  `claude/.claude/settings.overlay.json`): `mcp__atlassian__*` and
  `mcp__slack__*` are auto-allowed; the five destructive tools
  (`jira_delete_issue`, `jira_remove_issue_link`, `jira_remove_watcher`,
  `confluence_delete_page`, `confluence_delete_attachment`) are re-gated
  by exact name in `ask` (ask beats allow). Verified by
  `claude/.claude/tests/mcp-permission-overlay/run.sh`.
- qmd company-wiki posture (company overlay): the four read tools
  (`mcp__qmd__query`, `mcp__qmd__get`, `mcp__qmd__multi_get`,
  `mcp__qmd__status`) are auto-allowed by exact name so wiki queries skip the
  classifier. qmd indexing/write tools are intentionally not allowed --
  indexing stays a manual user action. The "when to query the wiki" directive
  lives in `claude/.claude/CLAUDE.company.md` (imported into the personal
  `CLAUDE.md`), not in settings. Verified by the same
  `mcp-permission-overlay` test.

Per-repo overrides live in `.claude/settings.local.json` (gitignored).
Add `permissions.ask` or `permissions.deny` rules there for sensitive
operations specific to that repo. Example:

```json
{
  "permissions": {
    "ask": [
      "mcp__claude_ai_Atlassian__*",
      "mcp__slack__slack_post_message"
    ]
  }
}
```

Local settings override base on a per-key basis (arrays concatenate).

### Semantic policy hook

`~/.claude/hooks/permission-policy.sh` runs on PreToolUse for
`Bash|Write|Edit|NotebookEdit|WebFetch`. It catches risky
shapes that the regex `allow`/`deny`/`ask` lists cannot express:

- shell-expanded secret paths (`$HOME/.ssh/*`, absolute `/Users/ben/.ssh/*`)
- `rm -rf` deny-list bypass forms (`\rm`, `command rm`, quoted forms,
  leading whitespace)
- curl/wget piped into a shell; base64/tar/gpg piped to curl/wget
- direct edits to live `~/.claude/` outside the dotfiles repo
- shell-init and persistence file edits (`~/.zshrc`, `~/.bashrc`,
  `~/.gitconfig`, LaunchAgents, crontab)
- WebFetch to dynamic-DNS / paste / webhook hosts, oversized query
  strings, base64-shaped payloads, URLs that reference local paths

The hook only emits `permissionDecision: "ask"` -- never `deny`. Hard
blocks stay in `permissions.deny` so they remain visible and version-
controlled. Disable the hook for a single shell with
`CLAUDE_PERMISSION_POLICY=off`; revert the PreToolUse registration in
`settings.base.json` for a permanent rollback.

Lib + tests follow the existing `commit-scope` convention:

- `claude/.claude/lib/permission-policy.sh` -- pattern matchers
- `claude/.claude/hooks/permission-policy.sh` -- dispatcher
- `claude/.claude/tests/permission-policy/run.sh` -- run with
  `bash run.sh` to verify all 13 cases pass

# Brewfile rules

- CLI tools: `brew "<name>"` -- keep sorted alphabetically.
- GUI apps: `cask "<name>"` -- keep sorted alphabetically.
- After adding an entry: `brew bundle --file=Brewfile`.
- No tap entries unless the formula is outside homebrew-core.

# Statusline (claude/.claude/statusline.sh)

- Test with mock JSON: `echo '{...}' | bash claude/.claude/statusline.sh | cat -v`
- Token fields live under `context_window.current_usage.{input_tokens,cache_creation_input_tokens,cache_read_input_tokens,output_tokens}` and `context_window.context_window_size`.
- `used_percentage` excludes output tokens; extract raw `current_usage` fields for any custom formula.
- `current_usage` is `null` before the first API call — all jq extractions from it need `// 0` fallbacks.
