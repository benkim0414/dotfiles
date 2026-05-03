# Codex wiki ingest workflow

Codex writes raw capture stubs to `${WIKI_VAULT}/raw/captures/` from the Stop hook. Treat those files as inbox items, not durable notes.

## Ingest steps

1. Open the latest raw capture and the referenced transcript.
2. Extract only durable learnings: repo conventions, recurring commands, debugging facts, architecture decisions, and non-obvious gotchas.
3. Write or update a curated wiki page in the relevant collection path. Keep one idea per section and prefer links back to code or docs over pasted transcripts.
4. Add frontmatter fields that help qmd retrieval, such as `title`, `tags`, `source`, and `updated`.
5. Remove or archive raw captures after curation according to the wiki repo's normal cleanup policy.

## What not to ingest

- Secrets, credentials, tokens, or private configuration.
- One-off command output that is not reusable.
- Large diffs or transcript excerpts. Link to code instead.
- Facts from web or MCP tools unless they were checked against primary sources and are still useful outside the session.

## Capture quality bar

A good curated note lets the next agent answer, "what should I know before touching this area?" without replaying the whole session. Keep raw captures lightweight and promote only stable knowledge.
