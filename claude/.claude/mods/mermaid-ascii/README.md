# mermaid-ascii

Draws ```` ```mermaid ```` fences in assistant replies as text art in the
terminal.

## Setup (once per machine)

The converter in `render/` (beautiful-mermaid on node) needs its
dependencies. Run this from the main checkout, not from a worktree:

```sh
npm ci --prefix ~/workspace/dotfiles/claude/.claude/mods/mermaid-ascii/render
```

Until then the mod shows the Mermaid source and shows a toast once per
session.

## Tests

- `claude plugin test claude/.claude/mods/mermaid-ascii` for the hooks.
- `claude/.claude/tests/mermaid-ascii/run.sh` for the converter and the Stow
  exclusion of `render/node_modules`. It exits 2 when `node` or `npm ci` is
  missing.

## Design

Intent, spec and plan: [`intent/render-mermaid-as-ascii/`](intent/render-mermaid-as-ascii/).
