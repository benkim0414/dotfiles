# Atomic commits + component scopes hardening design

**Date:** 2026-05-21
**Status:** Approved
**Source convention:** `docs/solutions/conventions/superpowers-spec-plan-commit-scopes-2026-05-19.md`

## Goal

Encode the component-scope convention permanently in the Claude Code workflow so future agents pick correct scopes without re-discovering the rule each time. Tighten the atomic-commits principle in `claude/.claude/CLAUDE.md` and back it with a non-blocking hook nudge in `git-safety.sh` that warns on anti-pattern scopes and suggests the right scope from staged file paths. Detection is signal-driven (filesystem + `git log`), not list-driven — no `BANNED_SCOPES` framework-name list to maintain, no `ARTIFACT_PREFIXES` per-framework list to extend. Same rule applies to Superpowers specs/plans, OpenSpec changes, and any future AI-skill convention that publishes to a documentation directory.

## Architecture

Three runtime layers (doc, lib, hook) plus a dedicated test suite. The lib carries no framework-specific scope list; it derives banned-scope judgments from four signals computed against the current repo's filesystem + git history.

1. **Doc layer** — `claude/.claude/CLAUDE.md` carries the human-readable rule + placeholder examples (`<component>`, `<repo-name>`). No literal scope names that go stale.
2. **Lib layer** — `claude/.claude/lib/commit-scope.sh` exposes `is_banned_scope` and `suggest_scope`. Internally uses a tiny `CONTAINER_NAMES` array (~12 standard filesystem container names like `docs`, `src`, `lib`, `bin`, `tests`, `scripts`) and otherwise derives everything from staged files + `git log` history of the current repo. No framework lists. No artifact-prefix lists.
3. **Hook layer** — `claude/.claude/hooks/git-safety.sh` sources the lib at commit time, parses the staged `-m` argument, and emits warnings via `emit_context`. No `exit 2`; warnings only.
4. **Test layer** — `claude/.claude/tests/commit-scope/` covers lib functions in isolation, hook-end-to-end behavior under synthesized PreToolUse JSON, and a sentinel test that protects required `CONTAINER_NAMES` entries.

The four signals replace the prior `BANNED_SCOPES` + `ARTIFACT_PREFIXES` lists:

- **S1 — Universal container** (static, tiny): scope is one of `docs`, `doc`, `src`, `lib`, `bin`, `scripts`, `script`, `tests`, `test`, `assets`, `static`, `public`, `vendor`, `build`, `dist`, `target`. These are filesystem conventions, ~30 years stable across codebases, not framework names.
- **S2 — Repo basename**: scope equals `$(basename $(git rev-parse --show-toplevel))`. Test override `COMMIT_SCOPE_REPO_NAME` for fixtures.
- **S3 — Path segment with history escape**: scope (or its singular/plural form) equals any directory segment of staged file paths, AND scope is NOT in `git log -100` history. Catches `docs(spec)` with `docs/.../specs/...` staged, `docs(openspec)` with `openspec/changes/...` staged, etc. Known-good components (e.g. real package dir `auth/` already used as scope in history) escape via the history check.
- **S4 — New scope advisory** (soft warning, separate emit): scope not in `git log -100` history AND not derived from staged paths. Emitted as a verify-this hint, not a ban.

New AI-skill framework appears (e.g. `dewy/proposals/`)? Caught by S3 automatically — `proposals` is a path segment. Zero lib edits.

## Components

### 1. CLAUDE.md commit rules

Replaces the current three-bullet block under `### Commit rules` (Git Workflow section) with four subsections:

- **Atomicity** — definition + four splitting heuristics ("and" / "also" in subject, multi-package staging, bug-fix + refactor combo, multi-comment PR feedback).
- **Staging** — selective-staging requirement; banned commands (`add -A`, `add .`, `add --all`, `add --update`, `commit -a`, `commit -am`); hook-enforced note.
- **Conventional commits** — form `type(scope): description`; type enum (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `perf`).
- **Scope = affected component, not artifact directory** — rule + four-signal explanation in plain English + canonical pointer to `claude/.claude/lib/commit-scope.sh`.

Closing examples block uses `<component>` and `<repo-name>` placeholders; one prose line clarifies the examples are illustrative — real scopes are whatever component names appear in the current repo's `git log`. One bad example per anti-pattern class (universal container, repo name, path-segment / framework name, multi-change subject).

### 2. `claude/.claude/lib/commit-scope.sh`

Pure POSIX-bash lib, no side effects on source. Repo-agnostic. Only static data is the universal-container list.

```bash
# S1: filesystem-convention container names. Stable across codebases for decades.
# These are container directory names, NOT framework names. Do not add 'spec',
# 'plan', 'openspec', etc. here -- those get caught by S3 (path-segment match).
CONTAINER_NAMES=(
  docs doc src lib bin scripts script
  tests test assets static public
  vendor build dist target
)
```

Helpers (private, prefixed `_`):

```bash
_repo_basename                    # echoes basename of git toplevel, honors COMMIT_SCOPE_REPO_NAME override
_known_scopes                     # echoes newline-separated scopes from `git log -100`, honors COMMIT_SCOPE_KNOWN_OVERRIDE
_is_container <scope>             # exit 0 if scope in CONTAINER_NAMES
_seg_matches_scope <scope> <seg>  # exit 0 if scope == seg, or singular/plural inflection matches
_path_segments <staged>           # echo distinct path segments of staged file list (one per line, .md stripped)
```

Public API:

```bash
is_banned_scope <scope> [<staged-files>]
```

Exit 0 (banned) if ANY signal fires:

1. `_is_container "$scope"` → S1 banned.
2. `[[ "$scope" == "$(_repo_basename)" ]]` → S2 banned.
3. `<staged-files>` provided, scope not in `_known_scopes`, AND scope (or singular/plural) matches any `_path_segments` entry → S3 banned.

Exit 1 otherwise. The history-escape on S3 lets legitimate component scopes that happen to share a name with a path segment (e.g. scope `auth` for `src/auth/login.ts` when `auth` already appears in `git log`) pass without false flags.

```bash
suggest_scope <staged-files>
```

Echo candidate scope (empty if none). Algorithm:

1. Single staged file matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}-(.+)\.md$` → strip `-design`/`-plan` suffix from group 1; set candidate = slug.
2. Else single top-level dir of staged files AND that dir is NOT in `CONTAINER_NAMES` → candidate = dir name.
3. Else echo empty.
4. Match candidate against each line of `_known_scopes`. Scope `S` matches candidate `C` iff `C == S`, `C` starts with `S-`, `C` contains `-S-`, OR `C` ends with `-S`. Longest match wins; echo it.
5. If no known scope matches, echo bare candidate (still useful — agent sees the slug).

No external dependencies beyond bash builtins + `awk`/`sort`/`tr` already used by the existing hook.

### 3. `git-safety.sh` extension

Two extension points in the existing hook, both inside the `git commit` branch:

**Banned-scope check** (new block after the `commit -a` block, before commit-on-main check):

```bash
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/commit-scope.sh"

msg=""
if [[ "$COMMAND" =~ -m[[:space:]]+\"([^\"]*)\" ]]; then
  msg="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ -m[[:space:]]+\'([^\']*)\' ]]; then
  msg="${BASH_REMATCH[1]}"
fi

declared_scope=""
if [[ "$msg" =~ ^[a-z]+\(([^)]+)\): ]]; then
  declared_scope="${BASH_REMATCH[1]}"
fi

staged_now=$(git diff --cached --name-only 2>/dev/null)

if [[ -n "$declared_scope" ]] && is_banned_scope "$declared_scope" "$staged_now"; then
  emit_context "PreToolUse" "Scope check: scope='${declared_scope}' is BANNED (filesystem container, repo basename, or path-segment match). Scope names a component, not a location. See CLAUDE.md > Commit rules > Scope."
fi
```

**Suggest + atomicity + new-scope advisory** (extends the existing staged-context block):

```bash
suggested=$(suggest_scope "$staged")
top_level_count=$(echo "$staged" | grep '/' | cut -d/ -f1 | sort -u | wc -l)

ctx="Staged files (${file_count}): ${staged}"
[[ -n "$dirs" ]] && ctx+=". Top-level directories: ${dirs}"
[[ -n "$known_scopes" ]] && ctx+=". Known scopes: ${known_scopes}"
[[ -n "$suggested" ]] && ctx+=". Suggested scope (derived): ${suggested}"
if (( top_level_count > 1 )); then
  ctx+=". ATOMICITY: staged files span ${top_level_count} top-level dirs. Verify ONE logical change; split if not."
fi

# S4 new-scope advisory
if [[ -n "$declared_scope" ]] \
   && ! is_banned_scope "$declared_scope" "$staged" \
   && ! echo "$known_scopes" | tr ',' '\n' | grep -qxF "$declared_scope" \
   && [[ "$declared_scope" != "$suggested" ]]; then
  ctx+=". NEW SCOPE: '${declared_scope}' not in git log history; suggested from paths is '${suggested:-<none>}'. Verify scope names a component."
fi

ctx+=". Pick scope by component, not artifact path. See CLAUDE.md > Commit rules > Scope."
emit_context "PreToolUse" "$ctx"
```

Heredoc / no-`-m` commits: `declared_scope` stays empty; banned-check + new-scope advisory skipped silently; suggest + atomicity still run. Editor-based commits land in the editor for human review anyway.

### 4. Tests

New directory `claude/.claude/tests/commit-scope/` mirroring `tests/read-once/` shape. Test IDs grouped by signal so commit boundaries fall cleanly:

```
run.sh helpers.sh
00-smoke-lib-sources.sh

# Lib-unit (commit 1)
10-s1-container-docs.sh                  # S1: docs banned
11-s1-container-src.sh                   # S1: src banned
12-s1-container-tests.sh                 # S1: tests banned
13-s2-repo-basename.sh                   # S2: COMMIT_SCOPE_REPO_NAME override banned
14-s3-path-segment-spec.sh               # S3: scope 'spec' with staged docs/.../specs/foo.md banned
15-s3-path-segment-plan.sh               # S3: scope 'plan' with staged docs/.../plans/foo.md banned
16-s3-path-segment-openspec.sh           # S3: scope 'openspec' with staged openspec/changes/foo banned
17-s3-history-escape.sh                  # S3: scope 'auth' matches src/auth segment BUT is in known_scopes -> not banned
18-good-component-passes.sh              # scope NOT in any signal -> not banned
20-suggest-from-date-slug.sh             # docs/superpowers/specs/2026-05-21-read-once-foo-design.md -> 'read-once' when in history
21-suggest-from-toplevel-dir.sh          # single staged file under 'auth/' top-level -> 'auth'
22-suggest-skips-container-toplevel.sh   # single staged file under 'docs/' top-level -> empty
23-suggest-multi-toplevel-empty.sh       # multi-top-level staged -> empty
24-suggest-no-known-match-echoes-slug.sh # date slug 'unknown-thing' with empty history -> echoes 'unknown-thing'
50-sentinel-container-list.sh            # CONTAINER_NAMES contains docs, src, lib, tests; lib is repo-agnostic (no 'dotfiles', no 'openspec')

# Hook-integration (commit 2)
60-hook-smoke.sh
61-hook-emits-banned-s1-docs.sh
62-hook-emits-banned-s2-repo-name.sh
63-hook-emits-banned-s3-path-segment.sh
64-hook-emits-suggest-from-date-slug.sh
65-hook-emits-atomicity-multi-toplevel.sh
66-hook-no-atomicity-single-toplevel.sh
67-hook-emits-new-scope-advisory.sh
68-hook-heredoc-skips-banned-check.sh
69-hook-single-quoted-msg-parsed.sh
70-hook-no-m-flag-skips.sh
```

Three test layers:

- **Lib unit** (IDs 00, 10-24, 50) — source `commit-scope.sh` directly, drive `is_banned_scope` + `suggest_scope` with fixture args + env overrides (`COMMIT_SCOPE_REPO_NAME`, `COMMIT_SCOPE_KNOWN_OVERRIDE`), assert return code / stdout. No git fixture needed.
- **Hook integration** (IDs 60-70) — `mktemp -d` git fixture, stage real files, synthesize PreToolUse JSON, pipe to `git-safety.sh`, grep stderr for expected emit substrings.
- **Sentinel** (ID 50) — assert `CONTAINER_NAMES` array contains the universal anchors `docs`, `src`, `lib`, `tests`. Assert the lib file does NOT contain framework-name literals (grep -v `spec`, `plan`, `openspec`, `dotfiles`, `proposal`, `rfc`, `prd` in array context) — protects the repo-agnostic guarantee.

`run.sh` iterates `[0-9][0-9]-*.sh`, prints `PASS/FAIL`, exits non-zero on any fail. Same shape as `tests/read-once/run.sh`.

Coverage rule: each signal (S1, S2, S3, S4) has at least one lib-unit test AND at least one hook-integration test. History-escape edge case (`17-s3-history-escape.sh`) is mandatory — protects legitimate scopes from false flags.

## Data flow

```
agent issues:  git commit -m "docs(spec): <subject>"
        │
        ▼
PreToolUse hook fires (Bash matcher)
        │
        ▼
git-safety.sh:
  parse -m argument           → msg = "docs(spec): <subject>"
  extract declared_scope      → "spec"
  staged_now := `git diff --cached --name-only`
        │
        ▼
is_banned_scope("spec", staged_now):
  S1 _is_container("spec")    → false ('spec' is NOT in CONTAINER_NAMES)
  S2 "spec" == repo basename  → false
  S3 staged contains 'specs/' segment, 'spec' is singular of 'specs'
     AND 'spec' not in `git log` history
                              → TRUE -> banned
  emit_context: "scope='spec' is BANNED ..."
        │
        ▼
(continues to staged-context emit:)
  suggest_scope(staged):
    single file matches YYYY-MM-DD-<slug>(-design)?.md
    slug = '<slug>'
    longest known-scope token match in slug → '<component>' or bare slug
  emit_context: "Staged files (1): ... Suggested scope (derived): <component> ..."
        │
        ▼
agent sees both warnings before commit lands
```

## Error handling

- Missing lib file: hook hits `set -uo pipefail` source failure → fails loud, agent notices, lib must ship together with hook. Acceptable.
- Malformed commit message (no `-m`, heredoc, mismatched quotes): banned-check + new-scope advisory skipped silently. Suggest + atomicity still emit on staged context.
- Empty staged list: existing hook returns before any new code runs. Same behavior.
- Fresh repo (no `git log` history): `_known_scopes` empty → history-escape in S3 doesn't fire; S3 may flag more aggressively in brand-new repos. Acceptable bootstrap friction.
- Outside a git repo: `_repo_basename` and `_known_scopes` return empty; S2 + S3 history-escape silently skipped; S1 still runs. Hook still useful.
- Malformed lib (someone re-introduces a framework-name list): sentinel test catches it.

## Testing

Run after each commit during implementation:

```sh
bash claude/.claude/tests/commit-scope/run.sh
```

After merge to main:

```sh
bash claude/.claude/tests/commit-scope/run.sh   # green
stow -t ~ -R claude
claude-sync
```

Live verification: stage a single file in a fresh session and dry-run a commit with `docs(spec): test`. Warning should appear in PreToolUse context emit. Cannot verify inside this session (PreToolUse fires in a child process; warning lands in the next agent turn).

## Rollout

Three atomic commits, each independently bisectable, each dogfooding the new principle:

1. `feat(claude): add signal-driven commit-scope lib`
   - `claude/.claude/lib/commit-scope.sh` with `CONTAINER_NAMES` + private helpers (`_repo_basename`, `_known_scopes`, `_is_container`, `_seg_matches_scope`, `_path_segments`) + public `is_banned_scope` / `suggest_scope`.
   - `claude/.claude/tests/commit-scope/{run.sh,helpers.sh}` + lib-unit cases 00, 10-18, 20-24, 50.
2. `feat(claude): wire commit-scope checks into git-safety hook`
   - `claude/.claude/hooks/git-safety.sh` extension (banned-check block + suggest/atomicity + new-scope advisory additions to staged-context emit).
   - Hook-integration test cases 60-70.
3. `docs(claude): document commit-scope rules in CLAUDE.md`
   - Replaces `### Commit rules` block in `claude/.claude/CLAUDE.md`.

Scope `claude` is correct on all three commits: lib + hook + doc all live under `claude/.claude/` and govern Claude-Code workflow. No multi-package staging.

## Out of scope

- Rewriting existing history. Prior convention doc handled that.
- Adding allow-list of known-good scopes (option C from brainstorming). Maintenance burden, rejected.
- Maintaining `BANNED_SCOPES` / `ARTIFACT_PREFIXES` framework-name lists. Replaced by signal-driven detection; framework-name drift eliminated.
- Generated CLAUDE.md block from lib data (prior option B). Without framework lists there's nothing left to mirror.
- Env-var kill switch (`COMMIT_SCOPE_DISABLE`). Hook is warn-only; no need.
- Scope enforcement at push time. PreToolUse on Bash is sufficient.
- Coverage for non-conventional commit subjects (e.g., `Merge branch` lines). Scope regex `^[a-z]+\(([^)]+)\):` does not match merge lines; they skip the banned-scope check naturally.

## Success criteria

- `commit-scope.sh` contains no framework-name literals: `grep -E 'spec|plan|openspec|proposal|rfc|prd|dotfiles' claude/.claude/lib/commit-scope.sh` returns no matches outside comments and error strings. Sentinel test enforces.
- `CONTAINER_NAMES` array contains the universal anchors `docs`, `src`, `lib`, `tests` plus the rest of the filesystem-convention set.
- `is_banned_scope` returns 0 for: scope in `CONTAINER_NAMES` (S1); scope == `_repo_basename` (S2); scope matching a staged-path segment when scope absent from `_known_scopes` (S3).
- `is_banned_scope` returns 1 for a scope that matches a staged-path segment when scope IS in `_known_scopes` (history-escape).
- `suggest_scope` derives candidate from date-prefixed filename slug OR top-level non-container dir; matches against `_known_scopes` history; echoes longest match or bare candidate.
- `bash claude/.claude/tests/commit-scope/run.sh` exits 0 with all cases PASS.
- A live commit attempt with `docs(spec): X` and a staged file under `docs/superpowers/specs/` produces a visible PreToolUse warning citing `BANNED` via S3 — regardless of repo.
- A live commit attempt with scope equal to the current repo's basename produces a `BANNED` warning via S2 — regardless of repo.
- A live commit attempt with scope `docs` produces a `BANNED` warning via S1 — regardless of repo.
- A live commit attempt with a new (not in `git log`) scope produces a soft `NEW SCOPE` advisory, not a `BANNED` warning.
- CLAUDE.md `### Commit rules` section renders the four subsections + four-signal explanation + canonical pointer + good/bad examples with `<component>` placeholders.
- No new hook entries in `settings.json` (extending existing `git-safety.sh` PreToolUse registration).
