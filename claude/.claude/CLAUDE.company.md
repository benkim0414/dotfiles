# Company configuration

Company-specific Claude Code instructions. Kept separate from personal
defaults in `CLAUDE.md`; imported from there via `@CLAUDE.company.md`.

## Company knowledge (qmd `wiki` collection)

The company knowledge base lives at `~/workspace/wiki` and is indexed by qmd
as the `wiki` collection (an OKF bundle: decisions, patterns, projects,
solutions, components, entities, sources).

- At the START of any non-trivial task, and whenever the topic shifts, run one
  `mcp__qmd__query` against collection `wiki` describing the task. Prefer
  lex + vec sub-queries; always set `intent`.
- When starting work in or about a project, query the wiki for that project's
  decisions and conventions before planning or implementing.
- Pull full documents with `mcp__qmd__get` when a hit is directly relevant.
- This is read-only company reference. Never run `qmd collection add`,
  `qmd embed`, or `qmd update` -- indexing is a manual user action.
