# Company wiki consultation via qmd — design

Date: 2026-06-19
Status: approved (brainstorming)

## Problem

Claude Code should consult the company knowledge base at `~/workspace/wiki`
to surface relevant company knowledge (decisions, patterns, projects, past
solutions) during a session. The configuration that enables this must live in
the **company layer** of the dotfiles repo, kept distinct from the user's
personal default configuration.

## Existing infrastructure (no change needed)

- `~/workspace/wiki` — an LLM-maintained knowledge base, OKF v0.1 bundle
  (Karpathy LLM-Wiki three-layer pattern), its own git repo. Sections under
  `okf/`: decisions, patterns, projects, solutions, components, entities,
  sources.
- `qmd` 2.1.0 already indexes it as the `wiki` collection (72 docs,
  `qmd://wiki/`, pattern `**/*.md`).
- The `qmd` MCP server is already registered in `~/.claude.json` (`qmd mcp`),
  exposing `mcp__qmd__query`, `mcp__qmd__get`, `mcp__qmd__multi_get`,
  `mcp__qmd__status`.

The gap is purely: (1) Claude is not told *when* to consult the wiki, and
(2) the qmd read tools are not auto-allowed, so under `defaultMode: auto`
each wiki query falls to the classifier and may prompt.

## Decisions

- **Separation mechanism: native `@import`.** Company instructions live in a
  new stowed file `claude/.claude/CLAUDE.company.md`. The personal
  `claude/.claude/CLAUDE.md` gains one `@CLAUDE.company.md` line. No
  `claude-sync` change. Company knowledge config is isolated in its own file;
  the personal file only references it.
- **Permissions: company overlay.** The four qmd **read** tools are added to
  the `allow` list in `claude/.claude/settings.overlay.json`, mirroring the
  existing atlassian/slack pattern. qmd indexing/write tools are NOT allowed
  (indexing stays a manual user action).
- **Trigger: instruction-only.** The always-loaded `CLAUDE.company.md`
  directive makes Claude query the wiki at the start of each task and on topic
  shifts. No hook. Zero per-turn cost; relevance is targeted to the task. A
  per-prompt auto-query hook was considered and rejected (per-turn latency +
  token cost + noise on trivial prompts).

## Components and file changes (all under `claude/.claude/`)

### 1. `CLAUDE.company.md` — NEW (company instructions)

Holds the wiki-consultation directive. Distinct from the existing
"Semantic Search (qmd)" section in the personal CLAUDE.md, which governs
per-project *code* collections — this directive is specifically the `wiki`
company-knowledge collection. Directive content:

- At the START of any non-trivial task (and when the topic shifts), run one
  `mcp__qmd__query` against collection `wiki` describing the task. Prefer
  lex + vec sub-queries; always set `intent`.
- When starting work in or about a project, query for that project's decisions
  and conventions before planning or implementing.
- Pull full docs with `mcp__qmd__get` when a hit is directly relevant.
- Read-only company reference. Never run `qmd collection add/embed/update` —
  indexing is a manual user action.

### 2. `CLAUDE.md` — one line added

A short "Company configuration" note containing `@CLAUDE.company.md`. Both
files stow to `~/.claude/`, so the import resolves
(`~/.claude/CLAUDE.md` → `~/.claude/CLAUDE.company.md`, relative to the
importing file's directory).

### 3. `settings.overlay.json` — qmd read tools added to `allow`

```json
"allow": [
  "mcp__atlassian__*",
  "mcp__slack__*",
  "mcp__qmd__query",
  "mcp__qmd__get",
  "mcp__qmd__multi_get",
  "mcp__qmd__status"
]
```

### 4. `tests/mcp-permission-overlay/run.sh` — extend assertions

Add a case asserting the four qmd read tools survive the base+overlay merge
into the generated `allow` list. Follows the repo's existing overlay-test
convention.

### 5. Project `CLAUDE.md` (dotfiles root) — docs update

Update the "Permission posture" and "Claude Code settings (layered merge)"
sections to record: qmd wiki read-tools auto-allowed via the company overlay,
and the `CLAUDE.company.md` `@import` as the company-instructions mechanism.

## Data flow

```
new task → Claude reads always-loaded CLAUDE.company.md directive
        → mcp__qmd__query(collection: "wiki", lex + vec, intent)
        → relevant hit? → mcp__qmd__get for full doc
        → proceed with company context in hand
```

## Out of scope / unchanged

- `qmd` MCP server registration (already in `~/.claude.json`).
- The wiki repo and its qmd index (already built).
- `claude-sync` logic — no code change; re-run it to regenerate
  `~/.claude/settings.json` after the overlay edit.
- No hooks added.

## Verification

- Run `claude-sync`; confirm `~/.claude/settings.json` `allow` contains the
  four qmd tools.
- `bash claude/.claude/tests/mcp-permission-overlay/run.sh` passes, including
  the new qmd assertion.
- Confirm `~/.claude/CLAUDE.md` resolves `@CLAUDE.company.md` (file stowed,
  symlink present).
- Sanity: in a fresh session, a company-flavored prompt triggers a `wiki`
  query without a permission prompt.
