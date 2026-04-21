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

```
/plugin uninstall pr@benkim0414
/plugin install pr@benkim0414
/reload-plugins
```

`/plugin install` copies the plugin into a versioned cache at
`~/.claude/plugins/cache/benkim0414/pr/<version>/` (a real copy, not a symlink
into the stow tree), and the running session loads from that cache. `/plugin
marketplace update benkim0414` only refreshes marketplace metadata -- it does
NOT re-copy the cached plugin payload, so edits to `claude/.claude/plugins/pr/`
will not take effect from that command alone. Uninstall + install rewrites the
cache; `/reload-plugins` then re-reads it without a session restart.

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
