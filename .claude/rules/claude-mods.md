---
paths:
  - "claude/.claude/mods/**"
  - "claude/.claude/tests/mermaid-ascii/**"
---

# Claude Code mods

- Each mod lives in `claude/.claude/mods/<name>/`. Its `README.md` holds its
  purpose, per-machine setup, and tests. Its `intent/` holds the spec and
  plan.
- A mod loads only when `CLAUDE_CODE_PLUGIN_DIRS` in the `env` block of
  `claude/.claude/settings.json` lists it (`~` allowed, entries separated by
  `:`). Add a new mod there. An interactive session watches the folder, so
  edits reload on their own.
- `node_modules` stays out of git and Stow: `.gitignore` covers
  `claude/.claude/mods/*/render/node_modules/`, and
  `claude/.stow-local-ignore` excludes it. That file replaces Stow's default
  ignore list, so it restates the defaults. Keep them when you add a line.
- Test hooks with `claude plugin test claude/.claude/mods/<name>`.
