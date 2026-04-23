---
description: "Ingest a source into the wiki: session learnings, URL, YouTube, file path, or topic research"
argument-hint: "[session | URL | raw/<path> | topic]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - WebFetch
  - WebSearch
  - AskUserQuestion
  - Agent
---

# Wiki Ingest

Acquire a source, create or update wiki pages, and maintain the index and log.
This implements the ingest operation from Karpathy's LLM wiki pattern.

All vault conventions (page types, frontmatter schema, naming rules, linking
rules) live in `$WIKI_VAULT/CLAUDE.md`. This skill reads that file at runtime
and defers to it for every convention-level decision. The procedure below
describes only the steps to follow.

## Preflight

1. Resolve vault path: `WIKI_VAULT="${WIKI_VAULT:-$HOME/workspace/wiki}"`.
   If the directory does not exist, abort with a clear error.
2. Read `$WIKI_VAULT/CLAUDE.md`. If it cannot be read, abort.

## Step 1: Acquire source

Determine the input type from $ARGUMENTS and follow the matching path.
Dispatch order: 1a (session) -> 1b (file path) -> 1c (YouTube) -> 1d (web URL) -> 1e (topic).

### 1a. Session learnings

If $ARGUMENTS is empty or equals "session":

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

**Self-check:** *"Would me-in-six-weeks benefit from this surfacing in a query
with no memory of this session? If no, skip it."*

If nothing passes, print "no durable learnings this session" and stop.

Write a raw transcript digest to
`$WIKI_VAULT/raw/transcripts/YYYY-MM-DD--<slug>--claude-code.md`:

```markdown
---
source: claude-code-session
created: YYYY-MM-DD
---

# Session: <one-line summary>

## Task
<2-4 sentences: what the user asked for and the goal.>

## What happened
<3-8 bullets: approach, dead-ends, surprises, outcome.>

## Learnings produced
<Populated after step 4 with [[wikilinks]] to created/updated pages.>
```

Proceed to step 2 with this raw file.

### 1b. File path

If $ARGUMENTS starts with `raw/` or is a file path:

- Read the file from `$WIKI_VAULT/raw/` (or the provided path).
- Extract metadata (title, author, date, URL) from YAML frontmatter.
- **Captures** (`raw/captures/*`): if the capture is primarily a URL, fetch it
  via 1c or 1d. If it is a thought/observation, proceed to step 2.
- Proceed to step 2.

### 1c. YouTube URL

If $ARGUMENTS matches a YouTube URL (`youtube.com/watch`, `youtu.be/`,
`youtube.com/live/`, `youtube.com/shorts/`):

1. Extract metadata and transcript with yt-dlp:
   ```bash
   yt-dlp --write-auto-sub --sub-lang en --skip-download \
     --print title --print channel --print upload_date --print description \
     -o "%(id)s" "$URL" 2>/dev/null
   ```
   If yt-dlp is unavailable, fall back to WebFetch.

2. Write to `$WIKI_VAULT/raw/transcripts/YYYY-MM-DD--<slug>--youtube.md`:
   ```markdown
   ---
   title: "Video Title"
   channel: "Channel Name"
   url: <URL>
   date: YYYY-MM-DD
   type: transcript
   fetched: YYYY-MM-DD
   ---

   ## Description
   <First 500 chars of description.>

   ## Transcript
   <Full transcript, organized into paragraphs.>
   ```

3. The file is immutable after creation. Proceed to step 2.

### 1d. Web URL

If $ARGUMENTS starts with `http://` or `https://`:

1. Fetch with WebFetch. Prompt: "Return the complete article as clean markdown.
   Preserve headings, code blocks, lists, links. Remove navigation, ads,
   sidebars. At the top output: TITLE: <title>, AUTHOR: <author or unknown>,
   DATE: <date or unknown>."

2. Write to `$WIKI_VAULT/raw/articles/YYYY-MM-DD--<slug>--<source>.md`:
   ```markdown
   ---
   title: "Article Title"
   author: "Author Name"
   url: <URL>
   date: YYYY-MM-DD
   type: article
   fetched: YYYY-MM-DD
   ---

   <Article content as returned by WebFetch.>
   ```

   Source slug: strip `www.` and TLD from domain (`blog.openai.com` -> `openai`,
   `*.substack.com` -> use subdomain).

3. The file is immutable after creation. Proceed to step 2.

### 1e. Topic research

If $ARGUMENTS is free text (no URL, no file path):

1. WebSearch for the topic. Get 5-10 candidates.
2. Filter: discard landing pages, marketing, paywalled teasers, duplicates.
   Prefer official docs, long-form posts, recent sources.
3. Select 2-4 sources. Confirm with AskUserQuestion before fetching.
4. Fetch each via 1c (YouTube) or 1d (web URL). Each becomes its own raw file.
5. Run steps 2-7 for each raw file. Dedup across sources naturally via step 3.
6. After all per-source processing, append a grouping entry to log.md:
   ```markdown
   ## [YYYY-MM-DD] Research: <topic>
   - **Query**: `<topic>`
   - **Sources ingested**: `raw/articles/...`, `raw/transcripts/...`
   - **Total pages touched**: N
   ```

## Step 2: Analyze source

Read the full raw file. Identify:
- Title, author, date, URL (if applicable)
- 3-7 key entities, concepts, or ideas
- Key claims or assertions
- Tags that apply (flat, lowercase, hyphenated)

## Step 3: Search existing pages

For each entity or concept identified in step 2:
1. Search `$WIKI_VAULT/pages/` by title (Glob) and tags (Grep in frontmatter).
2. If qmd MCP is available, also query with a paraphrase. Skip gracefully if
   qmd is not available or returns no results.
3. Classify each as: existing page to UPDATE, or new page to CREATE.

**Compounding rule:** if an entity or concept page already exists for the
subject, UPDATE it (append new information, add source to `sources` list,
bump `updated` date). Do not create a new page for something already covered.

For session ingests (1a), also apply the dedup self-check: if a learning is
already captured in an existing page, skip it and note "already captured in
[[Page Title]]" in the final summary.

## Step 4: Create or update pages

Read `$WIKI_VAULT/CLAUDE.md` for page type definitions, frontmatter schema,
body templates, and naming conventions. Follow them exactly.

### 4a. Summary page (one per raw source)

Always create one `type: summary` page for each raw source. Use the naming
convention from CLAUDE.md (source title with attribution).

### 4b. Entity and concept pages

For each entity or concept from step 2:

- **If the page exists**: read it, append new information to the relevant
  section, add the raw file to `sources`, set `updated` to today. Do not
  overwrite or delete existing content.
- **If the page does not exist** and the subject is substantial enough:
  create it following the body template from CLAUDE.md.

Target 3-8 pages created or updated per source (not counting the summary).

### 4c. Cross-linking

After writing all pages in the batch:
- Add `[[wikilinks]]` inline wherever one page mentions another.
- Ensure every page has a `## See also` section with at least one wikilink.
- Use red links (wikilinks to non-existent pages) for concepts that deserve
  a page but do not have one yet.

## Step 5: Update overview pages

If an overview page exists for any domain touched by this ingest
(`$WIKI_VAULT/pages/Overview -- <domain>.md`), update it:
- Add new pages to the appropriate section with one-line descriptions.
- Update the page count if shown.

If no overview exists and 3+ pages now share a tag, note this in the summary
as a candidate for a new overview page.

## Step 6: Update index.md

Read `$WIKI_VAULT/index.md`. For every page created or renamed in step 4:
- Add it under the appropriate domain section with `(type)` annotation and
  a one-line description.
- Update the `Pages: N` count and `Last updated` date.
- If a new domain section is needed (3+ pages share a tag), create it and
  move pages from `## Uncategorized`.

## Step 7: Append to log.md

Append one entry to `$WIKI_VAULT/log.md`:

```markdown
## [YYYY-MM-DD] Ingest: <Source Title>
- **Source**: `raw/<path>`
- **Created**: [[Page A]], [[Page B]], ...
- **Updated**: [[Page C]], ...
```

## Step 8: Review pass (session ingests only)

For session ingests (1a only), spawn one `feature-dev:code-reviewer` subagent.
Include the full text of every page written in steps 4a-4b. Instruct the
reviewer to check:

1. `type` field is valid and matches the page content.
2. `tags` has at least one entry; tags are consistent across related pages.
3. `sources` lists the correct raw file path(s).
4. `created` and `updated` dates are valid; `updated >= created`.
5. `## See also` exists on every page with at least one wikilink.
6. Code snippets are self-contained (every referenced variable is assigned
   in the block or annotated with `# defined elsewhere: <location>`).
7. The raw transcript path exists on disk.

Apply all findings with >= 70% confidence. Skip this step for URL/file/topic
ingests.

## Step 9: Summary

Print a table of what was written:

```
## Pages written

### Raw source
raw/<path>  [untracked / tracked]

### Summary
pages/<Summary Title>.md  (created)

### Entity / concept pages
| Page | Type | Action |
|------|------|--------|
| pages/<Title>.md | entity | created |
| pages/<Title>.md | concept | updated |

### Skipped (already captured)
[[Existing Page Title]]
```

Then print next steps:

```
## Next steps

1. cd "$WIKI_VAULT"
2. git diff --stat  (review what was written)
3. git add <files> && git commit -m "Ingest: <source title>"
4. (optional) qmd update && qmd embed
```
