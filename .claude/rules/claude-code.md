---
paths:
  - "claude/**"
  - "pi/**"
---

# Claude Code package (`claude/` → `~/.claude/`)

## Instruction layers

`claude/.claude/CLAUDE.md` is the global instruction file. It holds only the
commit rules and the worktree-first rule. Everything else belongs in the
project that needs it, so each repo runs the workflow that fits it.

## settings.json

- `claude/.claude/settings.json` is the one user settings file, stowed
  directly. Edit it in place; there is no generator.
- Claude Code writes to it at runtime (`/config`, `/effort`, theme, plugin
  installs). The writes land in the repo. Commit the ones worth keeping and
  `git checkout` the rest.
- Every machine shares this file. A hook for a tool that only some machines
  have must exit 0 when the tool is absent: see the Hindsight hooks
  (`[ -f "$f" ] && exec node "$f"; exit 0`).
- On a new machine, Claude Code creates its own `~/.claude/settings.json`,
  and Stow refuses to overlay it. Run `rm ~/.claude/settings.json`, or run
  `stow -t ~ --adopt claude`, review `git diff`, and `git checkout` what you
  do not keep.

## Global tools (kept light)

Every session gets RTK (see the root `CLAUDE.md`), one local hook, and two
vendored skills. User-scope MCP servers are device-local
(`~/.claude.json`), not part of this repo. `enabledPlugins` stays empty. Each repo enables its own plugins and MCP
servers; for repos shared with teammates, use the gitignored
`.claude/settings.local.json` and `claude mcp add --scope local`.

To make a plugin global anyway: add it under `enabledPlugins`, and add its
marketplace under `extraKnownMarketplaces` (`github` source + `repo`) unless
it is from the official Anthropic marketplace.

## git-stage-guard hook

`hooks/git-stage-guard.py` (`PreToolUse` on `Bash`) blocks broad staging:
`git add` with `-A`, `--all`, `-u`, `--update`, `--no-ignore-removal` or a
`.` pathspec, and `git commit -a`/`--all`. It enforces the staging rule in
the global `CLAUDE.md` and allows input it cannot parse. Tests:
`claude/.claude/tests/git-stage-guard/run.sh`.

## Vendored skills

Each is a verbatim copy. To update one, re-copy from upstream and record the
new commit here.

- `skills/eli5/`: `skills/eli5/SKILL.md` from
  [DreambigOu/ELI5](https://github.com/DreambigOu/ELI5) at `a766623b`. It
  writes prose for a named audience.
- `skills/show-me/`: `SKILL.md` and `agents/openai.yaml` from
  [humanlayer/skills](https://github.com/humanlayer/skills)
  `plugins/show-me/skills/show-me/` at `bba9d13a` (MIT). Runs only on
  `/show-me` (`disable-model-invocation: true`). A machine that ran
  `npx skills add` has a `~/.claude/skills/show-me` symlink into
  `~/.agents/skills/`: remove it before `stow -t ~ -R claude`.

## Output style

The global default is `ASD-STE100` (`output-styles/asd-ste100.md`, with
`keep-coding-instructions: true`): practical Simplified Technical English,
not certified compliance. The Pi package has the matching style. Keep both
bodies identical.

## Permission posture

The policy behind `permissions` in `settings.json`. The file is the source
of truth for the rule lists.

- Goal: reversible or non-destructive operations run without a prompt.
  Destructive or outward-facing ones prompt.
- `defaultMode: "auto"` sits under `permissions` (a top-level key is not
  documented). The classifier judges unmatched calls. `allow` skips the
  classifier. `ask` beats `allow`.
- Bash has no blanket allow. `allow` lists only reversible commands. Keep out
  commands whose arguments can destroy data (`git push`, `cp`, `mv`,
  `gh api`). `ask` gates destructive commands by text (`rm`, force pushes,
  `kubectl`/`terraform`/`helm` mutations, publishing, global `git config`).
- `deny` path rules use gitignore syntax (`Read(~/.ssh/**)`). They cover
  `cat`-style Bash reads, but not scripts that open files; that needs the
  sandbox.
- MCP: the `mcp__*__<verb>` server wildcard is valid only in `ask`/`deny`.
  `ask` globs gate destructive verbs (`delete`, `remove`, `sync`, `deploy`,
  `apply`, `patch`, `write`). Non-destructive verbs (`create`, `update`,
  `edit`, `add`, `transition`) fall to the classifier on purpose.
- `mcp__atlassian__*` and `mcp__slack__*` are allowed. Exact-name `ask` rules
  re-gate their destructive and outward-facing tools (Slack posts, Jira and
  Confluence deletes and moves, page restrictions).
- Per-repo overrides go in that repo's gitignored
  `.claude/settings.local.json`. Arrays concatenate with the user settings.

## Statusline (`statusline.sh`)

- Test with mock JSON: `echo '{...}' | bash claude/.claude/statusline.sh | cat -v`
- Token fields: `context_window.current_usage.{input_tokens,cache_creation_input_tokens,cache_read_input_tokens,output_tokens}`
  and `context_window.context_window_size`.
- `used_percentage` excludes output tokens. Use the raw `current_usage`
  fields for a custom formula.
- `current_usage` is `null` before the first API call, so every jq read from
  it needs a `// 0` fallback.
