# Wiki Stage: Mirror Generated Docs into ~/workspace/wiki/raw/

Date: 2026-06-22
Status: Approved design, pre-implementation

## Problem

Superpowers and compound-engineering plugins generate durable docs during
Claude sessions: `docs/superpowers/specs/`, `docs/superpowers/plans/`, and
`docs/solutions/` (ce-compound). These docs hold reusable design rationale and
problem->fix learnings, but they stay siloed in each source repo. The
`~/workspace/wiki` OKF knowledge base (indexed by qmd as the `wiki` collection)
is the place future sessions look for that institutional knowledge -- yet
session-generated docs never reach it without manual copying.

Goal: automatically stage generated docs into `~/workspace/wiki/raw/<repo>/`
after they are finalized, so a later `wiki /ingest` run can fold them into the
`okf/` knowledge pages.

## Scope

This design covers the **stage** half of the wiki's two-stage pipeline only:

- **Stage** (this design): copy a source doc verbatim into `raw/<repo>/...`.
  Mechanical, file-level, idempotent.
- **Ingest** (out of scope, already exists): the wiki's `/ingest` skill +
  `wiki-ingestor` agent fold raw docs into `okf/` pages. Deliberately
  single-writer and dedup-first (qmd + grep). This design does NOT automate it.

Semantic deduplication in `okf/` is the ingest layer's job. This design only
guarantees no duplicate files in `raw/`.

### Non-goals

- No automatic ingestion into `okf/`.
- No git commit or push into the wiki repo (copy-only; changes left
  uncommitted for a later session to review and commit).
- No pruning: a removed or renamed source doc leaves its `raw/` copy intact
  (deletion is manual). This prevents orphaning an `okf/` Source page's
  `resource:` pointer.

## Decisions (locked during brainstorming)

| Decision | Choice |
|---|---|
| Automation scope | Stage into `raw/` only; ingest stays manual |
| Trigger | Git `post-merge` -- stage only finalized docs that reached `main` |
| Doc set | Whole `docs/` tree per repo (no include-list config) |
| Wiki git action | Copy only, leave uncommitted; copy/update-only, never delete |
| Hook install | Per-repo `post-merge` shim (opt-in); dotfiles wired first |

Rationale for the trigger: in this repo's no-pr flow, docs become real when the
worktree branch merges into `main`. That merge is the natural "this is done,
stage it" signal. WIP on worktree branches is never staged. Because the mirror
is idempotent, repeated merges never duplicate, so over-firing is harmless.

## Architecture

Three pieces, all in the dotfiles `bin` package.

### `wiki-stage` (`bin/.local/bin/wiki-stage`)

The idempotent mirror. Repo-agnostic, safe to run anytime, also the manual /
backfill entrypoint.

Behavior:

1. Resolve the canonical repo identity, worktree-independent:
   - `common_dir=$(git rev-parse --git-common-dir)` -- points at the main
     repo's `.git` even when invoked from a linked worktree.
   - `repo_root=$(dirname "$common_dir")` -- the main worktree root.
   - `repo_name=$(basename "$repo_root")` -- e.g. `dotfiles`, never the
     worktree branch name.
2. `docs_root="$repo_root/docs"`. If it does not exist, exit 0.
3. `wiki_root="${WIKI_STAGE_DEST_ROOT:-$HOME/workspace/wiki}"`. If `wiki_root`
   does not exist, exit 0. `dest_base="$wiki_root/raw/$repo_name"`. The env
   override exists so tests never touch the real `~/workspace/wiki`.
4. Enumerate tracked docs: `git -C "$repo_root" ls-files docs/`. Tracked-only
   excludes untracked WIP/scratch from ever reaching `raw/`.
5. For each tracked file at `docs/<rel>`:
   - `dest="$dest_base/<rel>"` (strip the leading `docs/` segment).
   - Copy iff `dest` is missing OR its content hash differs from the source.
   - Never delete.
6. Exit 0.

### `post-merge` shim (per source repo `.git/hooks/post-merge`)

Tiny:

```sh
#!/usr/bin/env sh
exec wiki-stage
```

Not stowable (lives under `.git/`). Installed by `wiki-stage-install`.

### `wiki-stage-install` (`bin/.local/bin/wiki-stage-install`)

Writes the shim into a target repo's hooks dir.

- Default target: the current repo. Optional path arg for another repo.
- Resolve the hooks dir from `git rev-parse --git-common-dir` so it works when
  invoked from a worktree (hooks live in the common dir, not the worktree).
- If a `post-merge` already exists and is not our shim: refuse with a clear
  message (do not clobber husky / pre-commit / existing hooks).
- Otherwise write the shim and `chmod +x`.

## Data flow

```
merge into main  ->  post-merge fires (main worktree)
   ->  shim calls wiki-stage
         repo_name = basename(dirname(git --git-common-dir))
         docs_root = <main-worktree-root>/docs
         dest      = ~/workspace/wiki/raw/<repo>/<path-under-docs>
   ->  for each TRACKED file in docs/ (git ls-files):
         copy iff dest missing OR content hash differs
   ->  exit 0     # wiki working tree shows new/changed raw files, UNCOMMITTED
later (separate, manual):  wiki /ingest  ->  okf/ pages
```

Example mapping: `docs/superpowers/specs/X.md` ->
`raw/dotfiles/superpowers/specs/X.md`, matching the existing `raw/ops/` layout
in the wiki repo.

## Dedup / idempotency guarantee

The "no duplicates" property comes from how the mirror is keyed, independent of
the trigger:

- **Stable key**: destination is a pure function of the source-relative path;
  worktree prefixes normalized away via `--git-common-dir`. A doc never lands
  under two paths.
- **Content-hash skip**: byte-identical destination => no write. Re-runs are
  no-ops.
- **Tracked-only**: `git ls-files docs/` excludes untracked files.
- **Copy/update-only, never delete**: removed source docs retain their `raw/`
  copy.

## Error handling

`post-merge` is informational and must never fail a merge. `wiki-stage` exits 0
on every guard:

- Not a git repo, no `docs/` dir, or `~/workspace/wiki` absent -> quiet exit 0.
- Per-file copy error -> warn to stderr, continue, non-fatal.
- Wiki repo dirty or mid-ingest -> irrelevant; copy-only touches files, not git
  state.
- Fires on `git pull` merges too -> harmless (idempotent).

## Testing

- Tests at repo-root `tests/wiki-stage/run.sh`, kept out of the stow path so
  they do not symlink into `~/.local/bin`. Self-contained bash, exercising both
  scripts against temp repos and a temp wiki dir (override the wiki location via
  an env var, e.g. `WIKI_STAGE_DEST_ROOT`, so tests never touch the real
  `~/workspace/wiki`).
- Cases:
  1. Basic mirror: tracked docs appear under `raw/<repo>/...`.
  2. Idempotency: run twice -> second run writes nothing, no duplicate files.
  3. Changed file: edit a source doc, re-run -> raw copy updated in place.
  4. Untracked file in `docs/` is NOT mirrored.
  5. Invoked from a linked worktree -> repo name resolves to the canonical
     main-repo basename, not the worktree branch name.
  6. Deleted source doc -> existing `raw/` copy retained (no delete).
  7. `wiki-stage-install` refuses to clobber a foreign existing `post-merge`,
     and writes the shim when absent.
- `shellcheck` on `wiki-stage` and `wiki-stage-install`.

## File layout

```
bin/.local/bin/wiki-stage           # idempotent mirror + manual entrypoint
bin/.local/bin/wiki-stage-install   # per-repo post-merge shim installer
tests/wiki-stage/run.sh             # bash test harness (not stowed)
```

Plus a setup note in `CLAUDE.md` / README: wiring a repo = run
`wiki-stage-install` once.

## Acceptance criteria

- Running `wiki-stage` from dotfiles `main` mirrors all tracked `docs/` files
  into `~/workspace/wiki/raw/dotfiles/...` with the `docs/` prefix stripped.
- Re-running produces zero new writes and zero duplicate files.
- Untracked and deleted docs behave per the dedup rules above.
- A merge into `main` in a repo wired via `wiki-stage-install` triggers staging
  automatically; the merge itself never fails because of the hook.
- `tests/wiki-stage/run.sh` passes; `shellcheck` is clean.
