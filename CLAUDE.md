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

# Stow gotchas

- **Always pass `-t ~`**. There is no .stowrc; the default target is the parent dir (`~/workspace/`), not `~`.
- **Never `stow` from a worktree**. Stow resolves links relative to the package dir it is given, so stowing from `.claude/worktrees/<name>/` produces symlinks into a directory that disappears when the worktree is removed. Stow from the main checkout after merge.
- **A package's `tests/` needs `.stow-local-ignore`**. Stow links every top-level entry of a package, so `<package>/tests/` lands in `~/tests` unless excluded. The `zsh` package leaked this way for months (`~/tests -> workspace/dotfiles/zsh/tests`). `zsh`, `bin`, and `atuin` each carry a `.stow-local-ignore` holding `^/tests$`; `bin/tests/stow-hygiene/run.sh` fails if a package with `tests/` lacks one. Note that `.stow-local-ignore` **replaces** Stow's default ignore list rather than adding to it — that is why `git/.stow-local-ignore` re-states `\.git`, so its own `.gitignore` can stow.
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
- A package's tests live inside that package: `<package>/tests/<name>/run.sh` (`atuin/`, `bin/`, `zsh/`). The `claude/` package nests them one level deeper, at `claude/.claude/tests/<name>/run.sh`, because the whole package stows into `~/.claude/`. Suites share an `ok`/`bad` counter and `exit 0`/`exit 1`. `bad` fires only from a branch you wrote, so "could not check" looks identical to "checked and passed": when a file is missing or a `grep`/`git`/`jq` call fails, call `bad`, never fall through.

# Brewfile rules

- CLI tools: `brew "<name>"` -- keep sorted alphabetically.
- GUI apps: `cask "<name>"` -- keep sorted alphabetically.
- After adding an entry: `brew bundle --file=Brewfile`.
- No tap entries unless the formula is outside homebrew-core.

