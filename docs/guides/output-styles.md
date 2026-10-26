# Global output styles

Claude Code and Pi use `ASD-STE100` as the global default. The style follows
practical Simplified Technical English: short sentences, active voice, plain
words, and consistent terms. It preserves uncertainty and technical precision.
It does not claim certified compliance or reproduce ASD's approved dictionary.

The inspiration is [Karpathy's post](https://x.com/karpathy/status/2105819303471976479),
which recommends ASD-STE100 and describes a softer version for readability.
X blocked direct retrieval during research; an indexed reproduction supplied
that context. The style uses independently written rules based on the local
ASD-STE100 skill, rather than copied standard text.

## Tracked configuration

- Claude: `claude/.claude/output-styles/asd-ste100.md` and the `outputStyle`
  key in `claude/.claude/settings.json`.
- Pi: `pi/.pi/agent/output-styles/asd-ste100.md` and the `outputStyle`
  key in `pi/.pi/agent/output-styles/settings.json`.

Both Markdown files use the exact name `ASD-STE100`. Keep their contents
identical. Claude uses `keep-coding-instructions: true`. Pi ignores that
metadata field and always preserves its coding instructions.

## Deploy

Pi settings pin the output-styles package to commit
`66a5f4466bac18f99432340020116db9920cdfc6`, which supports symlinks.
The commit is available on the package repository's `task/global-output-styles`
branch. Keep it reachable until it merges upstream.

After reviewing and merging the task changes, deploy from the durable dotfiles
checkout. Inspect existing paths first. Stop on conflicts and preserve existing
configuration. Do not use `--adopt` or deploy from a temporary worktree.
Home-directory changes require separate authorization.

```sh
stow --no-folding --simulate --verbose -t "$HOME" claude pi
stow --no-folding -t "$HOME" claude pi
```

Restart Claude Code. Restart Pi or run `/reload`. Pi uses its configured Git
package and may need network access to obtain the pinned commit.

## Overrides and checks

In Claude, project or local `outputStyle` settings can override the global
setting. Inspect the active style in `/config`. Restore the global default by
removing the overriding key. Do not overwrite unrelated settings.

In Pi, `/output-style` displays the active style. `/output-style ASD-STE100`
saves a project-local selection. Local selections override shared project
settings, which override the personal default. Remove an overriding
`outputStyle` key and run `/reload` to inherit the global default again.

Pi's extension applies only in the interactive TUI. Print, JSON, RPC, and
separate agent processes do not receive these style instructions. Styles,
settings, and their directories support symlinks. Project resources still require
project trust.

After deployment, check a fresh project without overrides in each agent. Ask
for a short technical explanation. Confirm short, direct prose, preserved
technical terms, and no style announcement. Also confirm that an explicit
request for another format or language takes precedence.
