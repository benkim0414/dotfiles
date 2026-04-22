---
description: "Distill session learnings into atomic notes in the 2ndbrAIn vault"
argument-hint: "[topic]"
---

# Wiki Ingest — Session Learnings

Distill durable learnings from the current Claude Code session into the personal
knowledge vault. Write atomic notes + a raw transcript digest. Print a next-steps
checklist. Do not touch git, qmd, or `Log — Ingests.md` — the user handles those.

## Preflight

1. Resolve the vault path: `${WIKI_VAULT:-/home/benkim0414/workspace/2ndbrAIn}`.
2. Read `$WIKI_VAULT/CLAUDE.md` to load the vault's note conventions before writing
   anything. If the file cannot be read, abort with a clear error.

## Step 1: Distill

Reflect on the current conversation. Produce a shortlist of candidate learnings.

**Include:**
- A failure + resolution that took > 2 tool calls to figure out
- A non-obvious command, flag, or API behavior that would trip up a future reader
- A tool or framework quirk that contradicts intuition
- An architecture decision + rationale that is specific enough to be reusable
- A correction the user gave that applies beyond this session

**Exclude:**
- Play-by-play of what was done (belongs in git log / PR description)
- Restatements of content already in this project's CLAUDE.md or docs
- Transient task state (current branch, WIP, what's next)
- Generic advice not derived from a specific observed behavior this session

**Self-check per candidate:** *"Would me-in-six-weeks benefit from this note surfacing
in a qmd query with no memory of this session? If no, skip it."*

If nothing passes the filter, print "no durable learnings this session" and stop.
Do not write any files.

Target 3–8 notes maximum. Quality over quantity.

## Step 2: Dedup

For each candidate, call `mcp__qmd__query` scoped to the `2ndbrain` collection
using a paraphrase of the claim. If the top result is clearly the same claim (not
just related), skip creating a new note. Record it as "already captured as
[[existing title]]" in the final summary. When in doubt, create the new note —
duplicates are cheaper to merge than gaps are to reconstruct.

## Step 3: Write the raw transcript digest

Create one file at `$WIKI_VAULT/raw/transcripts/YYYY-MM-DD--<slug>--claude-code.md`
where:
- `YYYY-MM-DD` is today's date
- `<slug>` is a 2–5 word kebab-case description of the session topic (use ARGUMENTS
  if provided; otherwise infer from the conversation)

```markdown
---
tags:
  - type/log
  - topic/<primary-topic>
source: claude-code-session
created: YYYY-MM-DD
---

# Session Transcript — <one-line summary of the session>

## Task
<2–4 sentences: what the user asked for and the goal.>

## What happened
<3–8 bullets: approach, dead-ends, surprises, outcome. Compressed narrative —
not a turn-by-turn replay.>

## Learnings produced
- [[Atomic Note Title 1]]
- [[Atomic Note Title 2]]
```

No `## Links` section in the transcript digest — it lives in `raw/` and is not
part of the note graph.

## Step 4: Write atomic notes

For each learning, create one file in `$WIKI_VAULT/Resources/<topic>/`. Create
the subfolder if it doesn't exist. Existing topic folders: `Claude Code/`,
`Codex/`, `Kubernetes/`, `LLM Engineering/`.

**Filename:** Full descriptive sentence, title-cased, `.md`. The title must be a
complete claim, not a topic label.
- Good: `Claude Code Read-Once Hook Blocks Re-Reads Within 1200s.md`
- Bad: `Read Once Hook.md`

**Frontmatter:**
```yaml
---
tags:
  - type/claim
  - topic/<primary-topic>
created: YYYY-MM-DD
---
```

Rules:
- Exactly one `type/*` tag. Use `type/claim` for a specific observed behavior;
  `type/concept` for a general abstraction. Never `type/reference` (reserved for
  imported external docs) or `type/log` (reserved for log files).
- At least one `topic/*` tag. Match the vault's existing taxonomy where possible:
  `topic/claude-code`, `topic/kubernetes`, `topic/infrastructure`,
  `topic/automation`, `topic/llm-engineering`, `topic/knowledge-management`.
  Create a new `topic/x` only if nothing existing fits.
- Include `aliases: [...]` only if there are natural alternate search handles.
  Omit the field entirely when not needed — do not write `aliases: []`.
- `created` = today in `YYYY-MM-DD`.

**Body:** 50–300 words. One claim per note. Write the *why* and the *surprise
factor* — what would trip up a future reader. Do not restate the title verbatim
in the opening sentence.

**Links section (required on every note):**
```markdown
## Links

- Source: [[Session Transcript — <summary>]]
- Related: [[<adjacent note from qmd dedup queries>]]
```

The source wikilink ties the note back to the transcript digest. Related notes
come from the Step 2 qmd results. If no related notes exist, omit the Related
line — do not write "Related: —".

## Step 5: Summary

Print a table of what was written:

```
## Notes written

| File | Type |
|------|------|
| Resources/Claude Code/Note Title.md | type/claim |

Raw transcript: raw/transcripts/YYYY-MM-DD--<slug>--claude-code.md

Skipped (already captured): [[Existing Note Title]]
```

Then print the next-steps checklist for the user to run inside the vault:

```
## Next steps

1. cd /home/benkim0414/workspace/2ndbrAIn
2. git diff --stat  (review what was written)
3. /lint  (vault skill — catches frontmatter errors, broken wikilinks, orphans)
4. (optional) Update Resources/<topic>/MOC — <topic>.md to include the new notes
5. (optional) Append entry to Log — Ingests.md
6. git add <files> && git commit -m "feat(wiki): ingest session learnings on <topic>"
7. qmd update && qmd embed
8. qmd query "<paraphrase of one new learning>"  (verify retrieval)
```
