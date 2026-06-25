# wiki-stage husky-aware post-merge hook — design

Date: 2026-06-25
Status: design (awaiting review)
Repo: dotfiles (no-pr mode)

## Problem

`wiki-stage` mirrors a repo's git-tracked `docs/` tree into
`~/workspace/wiki/raw/<repo>/`. It is meant to fire automatically from a
`post-merge` hook installed by `wiki-stage-install`. It is not firing in the
two repos that feed the wiki, so `raw/` has drifted ~29 artifacts behind the
source repos (24 in green-energy-group, 5 in ops).

### Root cause

`wiki-stage-install` writes its shim to `.git/hooks/post-merge`. Both
green-energy-group and ops set `core.hooksPath` (husky v9):

- green-energy-group → `.husky/_`
- ops → `.husky`

When `core.hooksPath` is set, git **ignores `.git/hooks/` entirely**. Git runs
husky's `.husky/_/post-merge` wrapper, which sources a top-level
`.husky/post-merge` user hook — and neither repo has one. So the shim installed
by `wiki-stage-install` is dead: present, but never executed.

Confirmation: the missing artifacts are tracked on `main` in both repos (they
were merged and pulled locally), so the hook *would* have mirrored them had git
been able to see it. This is a tooling bug, not missing automation:
`wiki-stage-install` is not husky-aware.

## Goal

Make the existing automation actually fire, on this machine only, without
changing the team-shared product repos. Scope is **automation only** — the
manual OKF ingest backlog is handled in a separate run. (Note: because
`wiki-stage` sweeps the full tracked `docs/` tree on every fire, the *raw*
backlog self-heals on the next merge in each repo once the hook works; only the
`okf/` ingest backlog remains a manual `/ingest` task.)

## Approach

Teach `wiki-stage-install` to honour `core.hooksPath`, reinstall in both repos,
remove the dead shims, and add a regression test. All committed work lands in
dotfiles.

### 1. `wiki-stage-install` becomes husky-aware

- Read `core.hooksPath` (`git -C "$target" config --get core.hooksPath`).
- **If set** (husky / custom): install the user hook at
  `<repo_root>/.husky/post-merge`, where `repo_root` is the main worktree root
  (`dirname` of the resolved `--git-common-dir`). This single location works for
  both layouts:
  - green-energy-group (v9, `hooksPath=.husky/_`): the generated
    `.husky/_/post-merge` wrapper sources `../post-merge`, i.e.
    `.husky/post-merge`.
  - ops (`hooksPath=.husky`): git runs `.husky/post-merge` directly.
- **If unset**: keep current behaviour — write `.git/hooks/post-merge`.
- Preserve the existing "refuse to overwrite a foreign hook" guard. "Ours" is
  identified by the `exec wiki-stage` line; a hook present and ours →
  "already installed", exit 0.

### 2. Hook body (husky path)

```sh
#!/usr/bin/env sh
command -v wiki-stage >/dev/null 2>&1 || exit 0
exec wiki-stage
```

The `command -v` guard makes the hook a silent no-op for anyone without the
tool. (A failing `post-merge` cannot abort a merge — it has already happened —
but the guard avoids "command not found" noise.) `chmod +x`.

### 3. Local-only, never committed

`.husky/` is git-tracked in both repos, so a new `.husky/post-merge` would show
as untracked. `wiki-stage-install`, when it writes into a husky dir, also
appends an idempotent ignore entry to the repo's `.git/info/exclude`
(`/.husky/post-merge`). The hook stays on this machine; the team repos are
untouched. No PRs, no shared ownership.

### 4. Clean up the dead shims

When installing to the husky path, remove a stale `.git/hooks/post-merge` **only
if it is the wiki-stage shim** (`exec wiki-stage`). Never remove a foreign hook.
This clears the misleading "looks installed but never runs" state in
green-energy-group and ops.

### 5. Reinstall

Run the fixed `wiki-stage-install` in green-energy-group and ops. Verify each
`.husky/post-merge` exists, is executable, contains the guarded body, and that
`.git/info/exclude` carries the entry. Optionally trigger one `wiki-stage` run
to confirm raw/ begins to fill (this also closes the raw backlog).

### 6. Regression test

Add a case to `tests/wiki-stage/run.sh` covering a repo with
`core.hooksPath` set to a husky-style dir:

- install writes the hook to `.husky/post-merge` (not `.git/hooks/`),
- hook body contains the `command -v wiki-stage` guard and `exec wiki-stage`,
- `.git/info/exclude` gains `/.husky/post-merge`,
- idempotent re-install reports "already installed",
- a pre-existing foreign `.husky/post-merge` is refused.

## Out of scope

- The OKF `okf/` ingest backlog (separate manual `/ingest` run, single-writer).
- Any change to green-energy-group or ops tracked files.
- A wiki-side detector/queue (rejected: the merge-time hook is the chosen
  trigger; husky-independent alternatives were considered and declined).

## Files touched (dotfiles)

- `bin/.local/bin/wiki-stage-install` — husky-aware install + exclude + shim
  cleanup.
- `tests/wiki-stage/run.sh` — new husky-hooksPath case.

## Non-dotfiles side effects (uncommitted, local)

- `green-energy-group/.husky/post-merge` (+ `.git/info/exclude` entry, dead
  `.git/hooks/post-merge` removed).
- `ops/.husky/post-merge` (+ `.git/info/exclude` entry, dead
  `.git/hooks/post-merge` removed).

## Verification

- `bash tests/wiki-stage/run.sh` — all cases pass, including the new one.
- In each source repo: `.husky/post-merge` present + executable + guarded;
  `git status` clean (excluded); `.git/hooks/post-merge` no longer the dead
  shim.
- A real merge (or a manual `wiki-stage`) in each repo mirrors tracked `docs/`
  into `~/workspace/wiki/raw/<repo>/`.
