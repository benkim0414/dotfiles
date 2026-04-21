# Dotfiles

macOS/Linux dotfiles managed with GNU Stow and Homebrew.

# Commands

## Bootstrap (fresh machine)

```sh
brew bundle --file=Brewfile
mkdir -p ~/.local/bin
stow -t ~ bin                         # stow bin first (includes claude-sync)
mkdir -p ~/.claude/plugins            # prevent tree-folding (see stow gotchas)
claude-sync                           # merge base + work overlay, stow claude
mkdir -p ~/.codex
stow -t ~ codex                       # stow codex config
stow -t ~ bat eza ghostty git lazygit mise nvim ssh starship tmux yazi zsh
```

After stowing, register MCP servers globally so they are available in all
Claude Code projects (not just this repo). Use `mcp-add` (from the bin package)
to automatically wrap each server with mcp-compressor for token efficiency:

```sh
mcp-add sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking
```

Register the qmd semantic search server:

```sh
npm install -g @tobilu/qmd
mcp-add qmd -- qmd mcp
```

`mcp-add` defaults to `--scope user`. Use `mcp-add -s project <name> ...` or
`mcp-add -s local <name> ...` for project- or machine-scoped registration.
These write to `~/.claude.json` (user scope) or `.mcp.json` (project/local scope),
which are managed by Claude Code and cannot be stowed.

Register the Atlassian and Slack MCP servers (work laptop only):

```sh
mcp-add atlassian -- uvx mcp-atlassian
mcp-add slack -- npx -y @modelcontextprotocol/server-slack
```

These require credentials in the environment. On the work laptop, create `~/.env.op`
(not stowed) with `op://` references, then populate `~/.env.local` once:

```sh
# ~/.env.op format (fill in your actual 1Password vault/item paths):
# JIRA_URL=op://Work/Atlassian/url
# JIRA_USERNAME=op://Work/Atlassian/username
# JIRA_API_TOKEN=op://Work/Atlassian/password
# CONFLUENCE_URL=op://Work/Atlassian/url
# CONFLUENCE_USERNAME=op://Work/Atlassian/username
# CONFLUENCE_API_TOKEN=op://Work/Atlassian/password
# SLACK_BOT_TOKEN=op://Work/Slack MCP/password
# SLACK_TEAM_ID=op://Work/Slack MCP/team_id
mise-load-op ~/.env.op ~/.env.local
```

`~/.env.local` is auto-loaded by mise into every shell via the global `_.file` setting.
Re-run `mise-load-op` after token rotation.

## Claude Code plugins

The `claude/` stow package ships a private, local-only plugin at
`claude/.claude/plugins/pr/` exposing `/pr:create`, `/pr:review`, `/pr:address`,
and `/pr:merge`. Colon-namespaced slash commands are plugin-only in Claude Code;
user-level skills can only use the directory name.

On a fresh machine, register the local marketplace and install the plugin
once. These write to `~/.claude/settings.json` (`enabledPlugins`) and Claude
Code's internal known-marketplaces file -- neither is stowed:

```
/plugin marketplace add ~/.claude/plugins
/plugin install pr@benkim0414
```

Verify with `/plugin list` (should show `pr@benkim0414` enabled) and
`/pr:create --help`.

SKILL.md shell blocks reference setup scripts via `${CLAUDE_PLUGIN_ROOT}`, an
env var Claude Code sets to the plugin's installed directory. Setup scripts
source `$HOME/.claude/lib/portability.sh` directly (single source of truth,
shared with the hooks) rather than a per-plugin copy.

To update the plugin after editing files in `claude/.claude/plugins/pr/`:
`/plugin marketplace update benkim0414` (or restart the session).

## qmd (semantic code search)

qmd is a global MCP server that provides semantic search over indexed code
collections, reducing Claude Code token usage by avoiding repeated Glob/Grep/Read.

### Manual indexing workflow

Never automate `qmd collection add`, `qmd embed`, or `qmd update` --
indexing must always be run manually.

```sh
qmd collection add ~/workspace/my-project --name my-project
qmd embed                    # generate embeddings (first time)
qmd update                   # update changed files (subsequent)
qmd collection list          # see all collections
qmd status                   # index health
```

Collections are stored in `~/.cache/qmd/`. Re-run `qmd update` after
significant code changes to keep the index fresh.

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

# Stow gotchas

- **Always pass `-t ~`**. There is no .stowrc; the default target is the parent dir (`~/workspace/`), not `~`.
- **Before stowing `bin`**: run `mkdir -p ~/.local/bin` first. Otherwise Stow tree-folds and creates a directory symlink, which breaks other tools that install into `~/.local/bin`.
- **Before stowing `codex`**: run `mkdir -p ~/.codex` first. Same tree-folding issue -- Codex writes runtime state (history, logs) into `~/.codex/`.
- **Before stowing `claude` on a machine with no existing plugins**: run `mkdir -p ~/.claude/plugins` first. `claude/.claude/plugins/` contains the local `pr` plugin; without a pre-created target, stow tree-folds into a single symlink and Claude Code's plugin cache writes would land inside the dotfiles repo. `claude-sync` handles the rest of `~/.claude/` but does not create this dir.
- **Stow refuses absolute symlinks**. Files installed by external tools (claude, git-filter-repo, uv, uvx) must NOT be added to the bin package -- leave them as-is in `~/.local/bin`.
- **After restructuring a package dir**, use `stow -t ~ -R <package>` to clean up stale symlinks.

# Package conventions

- Each top-level directory is a Stow package mirroring the home directory layout.
- Config files are edited in-place in the package dir; symlinks make changes live immediately.
- Custom scripts go in `bin/.local/bin/` and must be executable.
- The `claude/` package stows to `~/.claude/` (hooks, rules, plugins, and project instructions). `settings.json` is generated by `claude-sync` -- not stowed directly. The `plugins/pr/` subtree is a local Claude Code plugin; see the plugin section above for activation.
- The `codex/` package stows to `~/.codex/` (config.toml, AGENTS.md, Starlark rules, notification hook). Requires `mkdir -p ~/.codex` before stowing.

# Claude Code settings (dual-repo merge)

Base settings live in `claude/.claude/settings.base.json`. Work-specific
additions live in `~/workspace/claude-skills/settings.overlay.json`.

Run `claude-sync` after editing either file to regenerate `~/.claude/settings.json`.
The script deep-merges arrays (concatenate + deduplicate) and objects (overlay wins).
Without claude-skills cloned, it copies the base as-is.

# Brewfile rules

- CLI tools: `brew "<name>"` -- keep sorted alphabetically.
- GUI apps: `cask "<name>"` -- keep sorted alphabetically.
- After adding an entry: `brew bundle --file=Brewfile`.
- No tap entries unless the formula is outside homebrew-core.
