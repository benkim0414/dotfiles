# Dotfiles

macOS/Linux dotfiles managed with GNU Stow and Homebrew.

# Commands

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

# Global tools (kept light)

Every Claude Code session gets only two tools. Anything else belongs to the
repo that needs it.

- **RTK** (`brew "rtk"`): a `PreToolUse` hook on `Bash` (`rtk hook claude`)
  rewrites supported commands (git, test runners, builds) to compact output.
  Failed runs keep their full output, retrievable with `rtk recall <id>`; run
  a command raw with `rtk bypass <cmd>`. Read/Grep/Glob bypass it. Defaults
  only -- no config file is stowed; telemetry is off unless opted in.
- **Hindsight** coding-agent integration: its `SessionStart`,
  `UserPromptSubmit` and `Stop` hooks are declared in
  `claude/.claude/settings.json` (pointing at
  `~/.hindsight/coding-agents/dist/`). Config lives in `~/.hindsight/coding-agent.json`:
  one `work` bank for `~/workspace`, `optInOnly`, `project:{gitProject}` tags.

One local hook also runs in every session. `git-stage-guard`
(`claude/.claude/hooks/git-stage-guard.py`, a `PreToolUse` hook on `Bash`)
blocks broad staging: `git add` with `-A`, `--all`, `-u`, `--update`,
`--no-ignore-removal` or a `.` pathspec, and `git commit -a`/`--all`. It
enforces the staging rule in `claude/.claude/CLAUDE.md`, and it allows input
it cannot parse. Tests: `claude/.claude/tests/git-stage-guard/run.sh`.

User-scope MCP servers (device-local, `~/.claude.json`) are limited to
`hindsight`, `atlassian` and `slack`. No plugin is enabled globally; the two
global skills, `eli5` and `show-me`, are vendored (see Plugins below).
Per-repo tools -- plugins, and MCP servers such as Serena, Nx, Terraform or
EKS -- are enabled only in that repo. For repos shared with teammates, put them in
the gitignored `.claude/settings.local.json` (plugins) and local-scope MCP
servers (`claude mcp add --scope local ...`) rather than committed
`.claude/settings.json` or `.mcp.json`.

# Stow gotchas

- **Always pass `-t ~`**. There is no .stowrc; the default target is the parent dir (`~/workspace/`), not `~`.
- **Before stowing `bin`**: run `mkdir -p ~/.local/bin` first. Otherwise Stow tree-folds and creates a directory symlink, which breaks other tools that install into `~/.local/bin`.
- **Before stowing `codex`**: run `mkdir -p ~/.codex` first. Same tree-folding issue -- Codex writes runtime state (history, logs) into `~/.codex/`.
- **Never `stow` from a worktree**. Stow resolves links relative to the package dir it is given, so stowing from `.claude/worktrees/<name>/` produces symlinks into a directory that disappears when the worktree is removed. Stow from the main checkout after merge.
- **Before stowing `claude` on a new machine**: Claude Code creates its own `~/.claude/settings.json`, and Stow refuses to overlay a non-symlink. Either `rm ~/.claude/settings.json` first, or run `stow -t ~ --adopt claude` to pull the machine's file into the repo, then review `git diff` and `git checkout` anything you do not want to keep.
- **A package's `tests/` needs `.stow-local-ignore`**. Stow links every top-level entry of a package, so `<package>/tests/` lands in `~/tests` unless excluded. The `zsh` package leaked this way for months (`~/tests -> workspace/dotfiles/zsh/tests`). `zsh`, `bin`, and `atuin` each carry a `.stow-local-ignore` holding `^/tests$`; `bin/tests/stow-hygiene/run.sh` fails if a package with `tests/` lacks one. Note that `.stow-local-ignore` **replaces** Stow's default ignore list rather than adding to it — that is why `git/.stow-local-ignore` re-states `\.git`, so its own `.gitignore` can stow.
- **Stow refuses absolute symlinks**. Files installed by external tools (claude, git-filter-repo, uv, uvx) must NOT be added to the bin package -- leave them as-is in `~/.local/bin`.
- **After restructuring a package dir**, use `stow -t ~ -R <package>` to clean up stale symlinks.

# Mods

Claude Code mods live in the `claude` package under `claude/.claude/mods/<name>/`
and load through `CLAUDE_CODE_PLUGIN_DIRS` in the `env` block of
`claude/.claude/settings.json` (`~` allowed; one entry per mod, separated by `:`).
An interactive session watches the folder, so edits reload on their own.

- **mermaid-ascii** draws ```` ```mermaid ```` fences in assistant replies as
  text art in the terminal. Its converter (`render/`, beautiful-mermaid on
  node) needs one step per machine, from the main checkout:
  `npm ci --prefix ~/workspace/dotfiles/claude/.claude/mods/mermaid-ascii/render`.
  Until then the mod shows the source and toasts once per session.
  Intent, spec and plan: `claude/.claude/mods/mermaid-ascii/intent/`.
- **context-bar** draws what fills the context window as a band above the
  prompt: a header (`90k of 1M · compacts at 99%`), one bar coloured by
  category, and a legend. It is off by default; `/context-bar` toggles it
  (`on` and `off` set it), and the choice is kept user-wide in the mod's
  `$.store`. Nothing to install. Intent, spec and plan:
  `claude/.claude/mods/context-bar/intent/`.
- **`node_modules` stays out of git and Stow.** `.gitignore` covers
  `claude/.claude/mods/*/render/node_modules/`, and `claude/.stow-local-ignore`
  excludes it from Stow. That file replaces Stow's default ignore list, so it
  restates the defaults; keep them when adding a line.
- **Tests:** `claude plugin test claude/.claude/mods/<name>` for the hooks,
  and `claude/.claude/tests/mermaid-ascii/run.sh` for the converter and the
  Stow exclusion (exits 2 when `node` or `npm ci` is missing).

# Package conventions

- Each top-level directory is a Stow package mirroring the home directory layout.
- Config files are edited in-place in the package dir; symlinks make changes live immediately.
- Machine-specific settings go in untracked `~/.zshenv.local`, `~/.zprofile.local` and `~/.gitconfig.local`, which the shared configs load only if present. They live outside the repo: never commit or stow them.
- Custom scripts go in `bin/.local/bin/` and must be executable.
- A package's tests live inside that package: `<package>/tests/<name>/run.sh` (`atuin/`, `bin/`, `zsh/`). The `claude/` package nests them one level deeper, at `claude/.claude/tests/<name>/run.sh`, because the whole package stows into `~/.claude/`. Suites share an `ok`/`bad` counter and `exit 0`/`exit 1`. `bad` fires only from a branch you wrote, so "could not check" looks identical to "checked and passed": when a file is missing or a `grep`/`git`/`jq` call fails, call `bad`, never fall through.
- The `claude/` package stows to `~/.claude/` (settings, statusline, themes, and instructions). `settings.json` is stowed directly like any other file.
- The `codex/` package includes `codex/.codex/config.base.toml` as a reference template. Manage the active `~/.codex/config.toml` manually; there is no sync command. Codex writes UI notices, plugin state, and local project trust entries into `config.toml`, so that file is intentionally ignored. When applying template settings to an existing config, preserve its device-local entries.

# Claude Code settings

User settings live in one file, `claude/.claude/settings.json`, stowed to
`~/.claude/settings.json`. Edit it in place; there is no generator.

Claude Code writes to this file at runtime (`/config`, `/effort`, theme,
plugin installs), and through the symlink those writes land in the repo.
Commit the ones worth keeping and `git checkout` the rest.

## Output style

The global default is `ASD-STE100`, a practical Simplified Technical English
style. Its instructions live in `claude/.claude/output-styles/asd-ste100.md`.
It keeps Claude Code's coding instructions with `keep-coding-instructions: true`.
The matching Pi style lives in its own Stow package. Keep both bodies identical.

The style favors short sentences, plain words, and consistent terms while
preserving technical precision and uncertainty. It does not certify compliance
with ASD's approved dictionary. Explicit user requests take precedence.

## Plugins

`settings.json` enables no plugins. Each repo that needs a plugin enables
it in its own settings (for shared repos, the gitignored
`.claude/settings.local.json`).

One global skill, `eli5`, is
[DreambigOu/ELI5](https://github.com/DreambigOu/ELI5)'s `skills/eli5/SKILL.md`,
copied verbatim at commit `a766623b` into `claude/.claude/skills/eli5/`. It
stows into `~/.claude/skills/eli5` next to the `skills` CLI's symlinks, and
the `skills` entry in `pi/.pi/agent/settings.json` makes Pi load that same
directory. To update it, re-copy the file from upstream and record the new
commit here. It replaced the `eli5@claude-community` plugin, which made HTML
picture explainers; DreambigOu's skill instead writes prose for a named audience.

The other global skill, `show-me`, is
[humanlayer/skills](https://github.com/humanlayer/skills)'
`plugins/show-me/skills/show-me/` (`SKILL.md` and `agents/openai.yaml`, MIT),
copied verbatim at commit `bba9d13a` into `claude/.claude/skills/show-me/`. It
explains the current topic with pseudocode, call trees, diagrams and small
HTML artifacts, and runs only on `/show-me` (`disable-model-invocation: true`).
To update it, re-copy both files from upstream and record the new commit here.
A machine that installed it with `npx skills add` has a
`~/.claude/skills/show-me` symlink into `~/.agents/skills/`: remove that
symlink before `stow -t ~ -R claude`, or Stow refuses to overlay it.

To make a plugin global, add it under `enabledPlugins` and -- unless it comes from the
official Anthropic marketplace -- its marketplace under
`extraKnownMarketplaces` (`github` source + `repo`).

Instructions layer separately from settings: `claude/.claude/CLAUDE.md` holds
the commit rules and the worktree-first rule, and nothing else. Everything else that used to live globally
now belongs in a project file, so each repo can run the workflow its
characteristics call for.

## Permission posture

User-scope defaults (in `claude/.claude/settings.json`):

- `permissions.defaultMode: "auto"` -- new sessions open in auto mode.
  The key must sit under `permissions`; a top-level `defaultMode` is not
  documented. A classifier judges unmatched tool calls; explicit `allow`
  entries skip the classifier, and `ask` rules still force a prompt.
- Goal: reversible or non-destructive operations run without a prompt;
  destructive or outward-facing ones prompt.
- Bash has no blanket allow. Built-in read-only commands (`ls`, `cat`,
  `grep`, read-only `git`, ...) need no rule. `allow` names a short list
  of reversible commands (`git add/commit/switch/fetch/stash push|pop`,
  `gh pr|issue|run` reads, `rg`, `jq`, `mkdir -p`, ...). Keep that list
  short: an allow rule skips the classifier, so do not allow commands
  whose arguments can destroy data (`git push`, `cp`, `mv`, `gh api`).
- `ask` gates destructive shell commands by text: every `rm`/`rmdir`,
  force pushes and pushes to main, `git stash drop|clear`, `kubectl
  apply|patch|replace|scale|delete`, `terraform apply|destroy`, `helm
  install|upgrade|uninstall`, publishing, and global/system/hooksPath/
  credential `git config` writes. Reversible operations (`gh issue
  close|lock`, `gh run cancel`, `gh workflow disable`, `chmod`, cron
  tools) are not gated.
- `deny` path rules use gitignore syntax: `*` is one level, `**` is
  recursive (`Read(~/.ssh/**)`). They also cover `cat`/`head`-style Bash
  reads, but not scripts that open files; that needs the sandbox.
- Most MCP tools are not pre-approved in `allow` (bare `mcp__*` is
  invalid there -- only `deny`/`ask` accept bare wildcards). Under
  `defaultMode: "auto"` the classifier judges each unmatched MCP call.
- `ask` rules gate destructive + high-impact MCP mutations: the
  `mcp__*__*delete*`, `*remove*`, `*sync*`, `*deploy*`, `*apply*`,
  `*patch*`, `*write*` globs (the `mcp__*__` server-segment wildcard is
  valid only in `ask`/`deny` -- `allow` requires a literal, glob-free
  server segment, so do not move these to `allow`). The non-destructive write verbs
  (`create`/`update`/`edit`/`add`/`transition`) are intentionally NOT
  globally gated -- under `defaultMode: auto` they fall to the
  classifier, and the atlassian and slack allows below cover them for
  those two servers.
- atlassian + slack MCP posture (same file): `mcp__atlassian__*` and
  `mcp__slack__*` are auto-allowed. Exact-name `ask` rules re-gate the
  destructive tools (`jira_delete_issue`, `jira_remove_issue_link`,
  `jira_remove_watcher`, `confluence_delete_page`,
  `confluence_delete_attachment`) and the outward-facing ones
  (`slack_post_message`, `slack_reply_to_thread`,
  `jira_create_customer_request`, `jira_move_issue`,
  `confluence_move_page`, `confluence_set_page_restrictions`). Ask beats
  allow.

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
