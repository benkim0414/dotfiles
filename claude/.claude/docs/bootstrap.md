## Bootstrap (Fedora)

```sh
sudo dnf install -y git curl stow zsh tmux gcc make
curl https://mise.run | sh                # install mise (per-user, ~/.local/bin)
export PATH="$HOME/.local/bin:$PATH"      # put mise on PATH for the rest of this shell
chsh -s "$(command -v zsh)"               # if login shell isn't already zsh
mkdir -p ~/.local/bin
stow -t ~ bin                         # stow bin first (includes claude-sync)
mkdir -p ~/.claude/plugins            # prevent tree-folding (see stow gotchas)
claude-sync                           # merge base + work overlay, stow claude
mkdir -p ~/.codex
stow -t ~ codex                       # stow codex config
stow -t ~ bat eza ghostty git lazygit mise nvim ssh starship tmux yazi zsh
mise install                          # provision node, lazygit, codex CLI per ~/.config/mise/config.toml
```

mise installs each tool under `~/.local/share/mise/installs/<tool>/<ver>/bin/`
and prepends those paths in `mise activate zsh` -- so `lazygit`, `codex`, and
any future mise-managed binary always resolve before zsh's `AUTO_CD` can fall
through to a same-named stow package directory in this repo.

GUI apps in `Brewfile` (`bitwarden`, `google-chrome`, `ghostty`, `raycast`,
`docker-desktop`, `claude`, `codex`) are macOS-only -- install on Fedora via
Flatpak, vendor RPMs, or copr. Not managed by this repo.

## Bootstrap (macOS)

```sh
brew bundle --file=Brewfile
mkdir -p ~/.local/bin
stow -t ~ bin                         # stow bin first (includes claude-sync)
mkdir -p ~/.claude/plugins            # prevent tree-folding (see stow gotchas)
claude-sync                           # merge base + work overlay, stow claude
mkdir -p ~/.codex
stow -t ~ codex                       # stow codex config
stow -t ~ bat eza ghostty git lazygit mise nvim ssh starship tmux yazi zsh
mise install                          # provision node, lazygit, codex CLI per ~/.config/mise/config.toml
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

The `claude/` stow package ships a local marketplace at `claude/.claude/plugins/`
with the `wiki` plugin (`/wiki:ingest`). The `pr` plugin (`/pr:create`,
`/pr:review`, `/pr:address`, `/pr:merge`) lives in a separate private repo
(`benkim0414/skills`, registered as the `skills` marketplace).
Colon-namespaced slash commands are plugin-only in Claude Code; user-level skills
can only use the directory name.

On a fresh machine, register both marketplaces and install their plugins. These
write to `~/.claude/settings.json` (`enabledPlugins`) and Claude Code's internal
known-marketplaces file -- neither is stowed:

```
/plugin marketplace add ~/.claude/plugins
/plugin install wiki@benkim0414
```

The `skills` marketplace is a private repo -- clone it first, then register it
by local path:

```sh
gh repo clone benkim0414/skills ~/workspace/benkim0414/skills
```

```
/plugin marketplace add ~/workspace/benkim0414/skills
/plugin install pr@skills
```

Verify with `/plugin list` and `/pr:create --help`.

`/plugin install` copies each plugin into a versioned cache at
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` (a real copy, not a
symlink). `/reload-plugins` reloads the cache without a session restart.

To update the wiki plugin after editing files in `claude/.claude/plugins/wiki/`:

```
/plugin uninstall wiki@benkim0414
/plugin install wiki@benkim0414
/reload-plugins
```

To update the pr plugin after pulling changes to the `benkim0414/skills` clone:

```sh
git -C ~/workspace/benkim0414/skills pull
```

```
/plugin uninstall pr@skills
/plugin install pr@skills
/reload-plugins
```

The `caveman` plugin (token-reduction via terse output) comes from the
upstream `JuliusBrussee/caveman` marketplace. Register it and install:

```
/plugin marketplace add JuliusBrussee/caveman
/plugin install caveman@caveman
```

`enabledPlugins` in `settings.base.json` already sets `"caveman@caveman": true`,
so caveman auto-activates at `full` intensity on session start after install.
To update caveman when upstream publishes a new version:

```
/plugin uninstall caveman@caveman
/plugin install caveman@caveman
/reload-plugins
```

Do **not** run caveman's standalone `install.sh` — it writes into
`~/.claude/hooks/`, which is stow-symlinked from this repo.

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
