---
description: "Distill session learnings into atomic notes in the configured wiki vault"
argument-hint: "[topic]"
---

# Wiki Ingest — Session Learnings

Distill durable learnings from the current Claude Code session into the personal
knowledge vault. Write atomic notes + a raw transcript digest. Print a next-steps
checklist. Do not touch git, qmd, or `Log — Ingests.md` — the user handles those.

## Preflight

1. Resolve the vault path from `$WIKI_VAULT`. If unset, abort:
   `WIKI_VAULT is not set — add it to the env block in ~/.claude/settings.json.`
2. Read `$WIKI_VAULT/CLAUDE.md`. This file is the source of truth for the vault's
   folder layout, tag taxonomy, filename rules, and frontmatter schema — defer to it
   for every convention-level decision below. If the file cannot be read, abort with
   a clear error.

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

For each candidate, call `mcp__qmd__query` with a paraphrase of the claim. Query
all collections (no collection filter) — this transparently includes any future
work-vault overlay. If the top result is clearly the same claim (not
just related), skip creating a new note. Record it as "already captured as
[[existing title]]" in the final summary. When in doubt, create the new note —
duplicates are cheaper to merge than gaps are to reconstruct.

## Step 3: Write the raw transcript digest and vault reference note

### 3a. Raw transcript digest

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

### 3b. Vault reference note

Create one vault note at `$WIKI_VAULT/Resources/<primary-topic-folder>/Session Transcript — <title>.md`.
This is the canonical target that atomic notes' `Source:` wikilinks will resolve to.

```markdown
---
tags:
  - type/reference
  - topic/<primary-topic>
created: YYYY-MM-DD
read: true
---

Session log for <2–4 sentences: task and outcome>.

## What happened

<Copy compressed narrative from 3a — 3–8 bullets.>

## Learnings produced

<List atomic notes as wikilinks — populated after step 4.>

## Links

- Raw: `raw/transcripts/YYYY-MM-DD--<slug>--claude-code.md`
- Related: [[<adjacent session or note from qmd query>]]
```

`read: true` because the session is self-generated — there is no unread backlog.

## Step 4: Write atomic notes

For each learning, create one file in the appropriate topic folder under the vault.
Pick the folder based on the vault layout described in `$WIKI_VAULT/CLAUDE.md`.
Create a new topic folder only if the vault's conventions allow it and nothing
existing fits.

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
  `type/concept` for a general abstraction. Never `type/reference` or `type/log`
  in atomic notes (those are reserved for the session reference note and log files).
- **Primary domain tag (required):** Derive one domain `topic/*` tag from the
  session's subject (e.g. `topic/claude-code`, `topic/kubernetes`). Every atomic
  note in the batch must carry this tag — do not let a sibling slip through without it.
- **Concern tags (consistent across batch):** Before writing any note, decide which
  concern tags apply to the batch as a whole (e.g. `topic/automation`, `topic/security`).
  Apply them uniformly — if one note in the batch gets `topic/automation`, every
  sibling that touches automation must too. Derive the concern set once; do not
  tag note-by-note in isolation.
- `aliases: [...]` only if there are natural alternate search handles.
  Omit entirely when not needed — do not write `aliases: []`.
- `created` = today in `YYYY-MM-DD`.

**Body:** 50–300 words. One claim per note. Write the *why* and the *surprise
factor* — what would trip up a future reader. Do not restate the title verbatim
in the opening sentence.

**Self-contained code snippets:** Every fenced code block must be runnable as
shown. Any variable referenced (`$FOO`, `${BAR}`) must either have its
assignment visible earlier in the same block, or carry an inline comment
`# defined elsewhere: <where>`. Atomic notes are read in isolation — a reader
cannot assume surrounding context from a script or hook file.

**Links section (required on every note):**
```markdown
## Links

- Source: [[Session Transcript — <title>]]
- Related: [[<sibling from this batch that shares a theme>]], [[<adjacent note from qmd>]]
```

`Source:` uses the wikilink title of the vault reference note created in step 3b
(not a raw file path). `Related:` must include:
1. **Sibling cross-links**: any other note produced in this same batch that shares
   a theme. After writing all notes in the batch, revisit each and add sibling
   links that belong. Do not treat batch notes as isolated.
2. **qmd hits**: related existing vault notes from the step 2 dedup queries.
If no related notes exist, omit the Related line — do not write "Related: —".

## Step 5: Review pass

Spawn one `feature-dev:code-reviewer` subagent. Pass it the full contents of all
files written in steps 3b and 4 and instruct it to check:

1. `type/*` is correct and `read: true` is set on the reference note.
2. Primary-domain tag is present on every atomic note.
3. Concern tags are consistent across siblings in the batch.
4. `## Links` section exists on every note; the `Source:` wikilink title matches
   the reference note title from step 3b (so it resolves without a broken link).
5. Sibling cross-links: atomic notes in this batch that share a theme link to
   each other in `Related:`.
6. Code snippets are self-contained (every referenced var assigned in the block
   or annotated with `# defined elsewhere: <location>`).
7. The raw transcript path cited in the reference note body exists on disk.

Return findings as confidence-graded issues; ≥70% confidence = must-fix.

Apply all ≥70% findings in-place. Then proceed to step 6. If the reviewer
reports zero must-fix issues, note that in the final summary.

## Step 6: Summary

Run `git -C "$WIKI_VAULT" status --short` and inspect the output before printing.

Print a table of what was written, grouped by category:

```
## Notes written

### Raw source
raw/transcripts/YYYY-MM-DD--<slug>--claude-code.md  [untracked]

### Reference note
Resources/<topic>/Session Transcript — <title>.md  [untracked]

### Atomic notes
| File | Type |
|------|------|
| Resources/<topic>/Note Title.md | type/claim |

### Skipped (already captured)
[[Existing Note Title]]
```

If the raw transcript appears as untracked in `git status`, surface this warning
at the top of the summary:

```
WARNING: raw transcript not yet tracked — commit it with the atomic notes or it
will be lost when the branch is cleaned up.
```

Then print the next-steps checklist for the user to run inside the vault:

```
## Next steps

1. cd "$WIKI_VAULT"
2. git diff --stat  (review what was written)
3. /lint  (vault skill — catches frontmatter errors, broken wikilinks, orphans)
4. (optional) Update Resources/<topic>/MOC — <Topic>.md. Place each note under
   the section whose theme matches the note's primary concern (git mechanics →
   Surfaces/Git, not Workflow; hooks → Tools, not Workflow). When in doubt, open
   the MOC and place the entry adjacent to its closest sibling by topic.
5. (optional) Append entry to Log — Ingests.md
6. git add <files> && git commit -m "Ingest session learnings: <topic>"
   (include raw transcript, reference note, and all atomic notes in one commit)
7. qmd update && qmd embed
8. qmd query "<paraphrase of one new learning>"  (verify retrieval)
```
