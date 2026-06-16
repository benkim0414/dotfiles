# Hooks: comments, Google shell-style conformance, and README

Date: 2026-06-16
Status: design (awaiting user review)

## Problem

`claude/.claude/hooks/` holds 13 hook scripts plus 5 shared libs in
`claude/.claude/lib/`. The scripts work but are uneven: comment depth
varies, none use a `main()` wrapper, formatting is not normalized, and
there is no single document describing what each hook does, when it
fires, and how to run its tests. A reader (or future maintainer) has to
reverse-engineer the wiring from `settings.base.json`.

## Goals

1. Every hook and lib file carries a consistent header block and section
   comments so its purpose, trigger, and exit-code contract are clear
   without reading the body.
2. All hooks and libs conform to the Google Shell Style Guide
   (https://google.github.io/styleguide/shellguide.html), including
   `shfmt` formatting, with one documented deviation (shebang).
3. A `README.md` under the hooks directory documents all hooks (grouped
   by event), the shared lib helpers, and how to run the test suites.

## Non-goals

- **No file renames.** Hook filenames are referenced from
  `settings.base.json`, the work overlay, `claude-sync`, test suites,
  `docs/`, and `CLAUDE.md`. Renaming a file means updating every
  reference or the hook silently stops firing. Out of scope.
- **No behavior changes.** This is a readability + conformance pass.
  Hook logic, exit codes, and emitted output stay identical.
- **No new test suites.** Existing suites are the regression net; we do
  not add coverage for currently-untested hooks (that was offered as
  approach C and declined).

## Inventory

### Hooks (`claude/.claude/hooks/`), grouped by event

| Event | Matcher | Hook |
| --- | --- | --- |
| SessionStart | — | `git-session-start.sh` |
| UserPromptSubmit | — | `resolve-pr-refs.sh` |
| PreToolUse | `Read\|NotebookRead\|mcp__qmd__get\|Bash\|Grep` | `read-once.sh` |
| PreToolUse | `Bash` | `git-safety.sh` |
| PreToolUse | `Write\|Edit\|NotebookEdit` | `worktree-guard.sh` |
| PreToolUse | `Bash\|Write\|Edit\|NotebookEdit\|WebFetch` | `permission-policy.sh` |
| PreToolUse / Notification | `AskUserQuestion\|ExitPlanMode` (+ Notification) | `notify.sh` (async) |
| PostToolUse | `EnterWorktree` | `worktree-entered.sh` |
| PostToolUse | `ExitWorktree` | `worktree-exited.sh` |
| PostToolUse | mutating + read tools | `audit-log.sh` (async) |
| PostToolUseFailure | — | `failure-recovery.sh` |
| SessionEnd | — | `read-once-gc.sh` |
| PostCompact | — | `restore-git-context.sh` |

The implementer MUST derive the authoritative event/matcher for each
hook from `settings.base.json` (and the work overlay if present), not
from this table alone — the table is the design-time snapshot.

### Libs (`claude/.claude/lib/`)

| File | Role |
| --- | --- |
| `commit-scope.sh` | commit-scope signal validation (S1-S4) used by `git-safety.sh` |
| `permission-policy.sh` | pattern matchers used by `permission-policy.sh` hook |
| `portability.sh` | cross-platform helpers (`file_mtime`, `run_timeout`) |
| `read-once-cache.sh` | read-once cache record/lookup/deny helpers |
| `session.sh` | session-id parsing, context emit, worktree/workflow helpers |

### Test suites (`claude/.claude/tests/`)

`commit-scope/`, `permission-policy/`, `read-once/`, `session-lib/` —
each has `run.sh` iterating `cases/*.sh`. These cover `git-safety.sh`,
`read-once.sh`, and the four corresponding libs. The remaining ~9 hooks
have no dedicated suite and are verified by `shellcheck` + manual smoke.

## Decisions (locked with user)

- **Renaming:** functions/variables only, no files.
- **Comment depth:** header block + section comments (not line-by-line).
- **README scope:** hooks + libs + test-running instructions.
- **Style scope:** full Google conformance including `shfmt`.
- **Shebang:** keep `#!/usr/bin/env bash`. Google §2 mandates
  `#!/bin/bash`, but macOS ships bash 3.2 at `/bin/bash`; Homebrew bash 5
  lives outside `/bin`. `env bash` is the correct portable choice for
  cross-platform dotfiles. Documented as a justified deviation.

## Approach (tooling-first: mechanical, then semantic)

Chosen approach A. Rationale: separating the mechanical reformat from
hand-written semantic edits keeps each diff reviewable and confines
behavior risk to a pass that tools verify. This mirrors the existing
`docs/solutions/design-patterns/behavior-preserving-bash-hook-dedup-2026-06-16.md`
discipline.

### Step 1 — Tooling

Add `shfmt` to `Brewfile` (alphabetical, `brew` section) and install.
`shellcheck` 0.11.0 is already present.

### Step 2 — Format pass (mechanical, behavior-preserving)

Run `shfmt -i 2 -ci -bn -w` on all 13 hooks + 5 libs. Resolve any
`shellcheck` findings that surface, restricting changes to ones with no
behavior effect (quoting, `[[ ]]`, `$(...)`, `local` declarations).
Verify before committing:

- all 4 test suites green,
- `shellcheck` clean on every hook + lib,
- manual smoke (pipe representative JSON to each untested hook, confirm
  identical exit code + output vs. pre-change).

### Step 3 — Comment + structure pass (semantic)

For each hook and lib:

- **File header block**: purpose, triggering event + matcher (hooks),
  exit-code contract (e.g. `Exit 0 = allow; Exit 2 = block`), async note
  where applicable. Note the `env bash` deviation once (README is the
  canonical place; headers may cross-reference).
- **Section comments**: short markers on logical blocks (already partly
  present in several hooks — bring all to the same standard).
- **`main()` wrapper** (§7.7): wrap top-level execution for any script
  that defines ≥1 function. Straight-line scripts with no functions do
  not require `main()`.
- **Per-function comment blocks** (§4.2): `Globals` / `Arguments` /
  `Outputs` / `Returns` on lib functions where non-obvious. Keep
  existing library prefixes (`rc_`, `emit_`, `_repo_basename`); they
  already satisfy the guide's namespacing intent — no renames for their
  own sake.

Verify identically to Step 2 after this pass.

### Step 4 — README

Create `claude/.claude/hooks/README.md`:

- **Overview**: what hooks are, how they are registered (`settings.base.json`
  + overlay, regenerated by `claude-sync`), exit-code conventions.
- **Hooks by event**: one subsection per event (SessionStart,
  UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure,
  SessionEnd, PostCompact). Each hook: matcher, one-line purpose,
  exit/async behavior, libs it sources.
- **Shared libs**: table of the 5 libs and the helpers they expose.
- **Tests**: how to run each suite (`bash run.sh` per dir) and what each
  covers; note which hooks are smoke-only.
- **Style**: Google Shell Style Guide reference + the documented
  `env bash` deviation.

### Step 5 — Final verification

- 4 test suites green.
- `shellcheck` clean on all hooks + libs.
- `shfmt -d` reports zero diff on all hooks + libs.
- `stow -t ~ -R claude` re-link sanity (symlinks intact, no breakage).

## Commit strategy

Per repo atomic-commit rules, scope = affected component. The hooks and
libs live in the `claude` package; `git log` history uses `claude` for
this component (`docs(claude)`, `refactor(claude)`). The Brewfile change
is the one exception — it touches the `brewfile` component. Planned
commits (writing-plans may refine granularity):

1. `chore(brewfile): add shfmt formatter`
2. `style(claude): shfmt-format hooks and libs` (mechanical pass)
3. `docs(claude): add header + section comments and main() wrappers`
   (may split per-file if diffs are large)
4. `docs(claude): add hooks README`

Scope `claude` names the affected component as established in `git log`
history, satisfying signals S1-S4 in `commit-scope.sh`. (`hooks` would
trip S3 — it matches the `hooks/` path segment and is absent from
history.)

## Risks

- **Untested hooks during reformat.** Mitigated by the mechanical/
  semantic split, `shellcheck`, `shfmt -d`, and manual smoke tests.
- **`shfmt` reformat altering heredocs/quoting semantics.** `shfmt`
  preserves heredoc bodies; the smoke + suite pass catches regressions.
- **Overlay drift.** If the work overlay registers a hook on an event
  not in `settings.base.json` (e.g. `notify.sh` on Notification), the
  README must reflect it — implementer reads both sources.
