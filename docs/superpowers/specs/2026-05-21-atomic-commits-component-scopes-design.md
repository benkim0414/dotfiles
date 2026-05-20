# Atomic commits + component scopes hardening design

**Date:** 2026-05-21
**Status:** Approved
**Source convention:** `docs/solutions/conventions/superpowers-spec-plan-commit-scopes-2026-05-19.md`

## Goal

Encode the component-scope convention permanently in the Claude Code workflow so future agents pick correct scopes without re-discovering the rule each time. Tighten the atomic-commits principle in `claude/.claude/CLAUDE.md` and back it with a non-blocking hook nudge in `git-safety.sh` that warns on anti-pattern scopes and suggests the right scope from staged file paths. Cover spec/plan artifacts produced by Superpowers, OpenSpec, and any future AI-skill convention that publishes to a documentation directory.

## Architecture

Three runtime layers (doc, lib, hook) plus a dedicated test suite. Single source of truth for the scope rules lives in the lib bash arrays; doc + tests reference it.

1. **Doc layer** — `claude/.claude/CLAUDE.md` carries the human-readable rule + illustrative examples.
2. **Lib layer** — `claude/.claude/lib/commit-scope.sh` declares `BANNED_SCOPES` + `ARTIFACT_PREFIXES` bash arrays and exposes `is_banned_scope` and `suggest_scope` functions. Canonical machine-readable list.
3. **Hook layer** — `claude/.claude/hooks/git-safety.sh` sources the lib at commit time, parses the staged `-m` argument, and emits warnings via `emit_context`. No `exit 2`; warnings only.
4. **Test layer** — `claude/.claude/tests/commit-scope/` covers lib functions in isolation, hook-end-to-end behavior under synthesized PreToolUse JSON, and a sentinel test that protects required `BANNED_SCOPES` entries.

CLAUDE.md cites the lib path as the canonical list. CLAUDE.md examples stay illustrative and stable. A sentinel test asserts the bash array still contains the required entries.

## Components

### 1. CLAUDE.md commit rules

Replaces the current three-bullet block under `### Commit rules` (Git Workflow section) with four subsections:

- **Atomicity** — definition + four splitting heuristics ("and" / "also" in subject, multi-package staging, bug-fix + refactor combo, multi-comment PR feedback).
- **Staging** — selective-staging requirement; banned commands (`add -A`, `add .`, `add --all`, `add --update`, `commit -a`, `commit -am`); hook-enforced note.
- **Conventional commits** — form `type(scope): description`; type enum (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `perf`).
- **Scope = affected component, not artifact directory** — rule + anti-pattern table + canonical-list pointer to `claude/.claude/lib/commit-scope.sh`.

Closing block contains 5 good examples and 5 bad examples in a code fence, one bad example per anti-pattern class (artifact-type, repo-name, framework-name, location, multi-change).

### 2. `claude/.claude/lib/commit-scope.sh`

Pure POSIX-bash lib, no side effects on source. Two top-level arrays:

```bash
BANNED_SCOPES=(
  spec plan "spec, plan"
  dotfiles
  openspec proposal rfc prd
  specs plans changes
  docs doc src lib
)

ARTIFACT_PREFIXES=(
  docs/superpowers/specs
  docs/superpowers/plans
  docs/solutions
  openspec/changes
)
```

Two functions:

```bash
is_banned_scope <scope>
```
Returns 0 if `<scope>` matches any entry in `BANNED_SCOPES`; returns 1 otherwise. Used by hook for the banned-scope warning path.

```bash
suggest_scope <staged-file-list> <known-scopes-csv>
```
Echoes a scope candidate to stdout (empty if no confident match). Algorithm:

1. Collect top-level directories of staged files.
2. If single top-level dir AND dir name appears as an exact comma-separated token in `<known-scopes-csv>` → echo dir name.
3. Else if all staged files share one `ARTIFACT_PREFIXES` entry → derive slug from path after the prefix:
   - For paths under `docs/superpowers/specs|plans` or `docs/solutions/<sub>`: strip leading `YYYY-MM-DD-`, strip trailing `-design.md`, `-plan.md`, `.md`.
   - For paths under `openspec/changes`: first path segment after `changes/`.
4. Match slug against each known scope. Scope `S` matches slug `X` iff: `X == S` OR `X` starts with `S-` OR `X` contains `-S-` OR `X` ends with `-S`. Longest matching known scope wins.
5. Else echo empty.

No external dependencies beyond bash builtins + `awk`/`sort` already used by the hook.

### 3. `git-safety.sh` extension

Two extension points in the existing hook, both inside the `git commit` branch already at lines 76-103 / 195+:

**Banned-scope check** (new block immediately after the `commit -a` block, before main commit-on-main check):

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

if [[ -n "$declared_scope" ]] && is_banned_scope "$declared_scope"; then
  emit_context "PreToolUse" "Scope check: scope='${declared_scope}' is BANNED (artifact-type or repo-name scope). Pick component from doc contents. See CLAUDE.md > Commit rules > Scope."
fi
```

**Suggest + atomicity** (extends the existing staged-context block at line 195+):

```bash
suggested=$(suggest_scope "$staged" "$known_scopes")
top_level_count=$(echo "$staged" | grep '/' | cut -d/ -f1 | sort -u | wc -l)

ctx="Staged files (${file_count}): ${staged}"
[[ -n "$dirs" ]] && ctx+=". Top-level directories: ${dirs}"
[[ -n "$known_scopes" ]] && ctx+=". Known scopes: ${known_scopes}"
[[ -n "$suggested" ]] && ctx+=". Suggested scope (from paths): ${suggested}"
if (( top_level_count > 1 )); then
  ctx+=". ATOMICITY: staged files span ${top_level_count} top-level dirs. Verify ONE logical change; split if not."
fi
ctx+=". Pick scope by component, not artifact path. See CLAUDE.md > Commit rules > Scope."
emit_context "PreToolUse" "$ctx"
```

Heredoc / no-`-m` commits: `declared_scope` stays empty, banned check skipped silently, suggest + atomicity still run. Editor-based commits land in the editor for human review anyway.

### 4. Tests

New directory `claude/.claude/tests/commit-scope/` mirroring `tests/read-once/` shape. Test IDs grouped by layer so commit boundaries fall cleanly:

```
run.sh helpers.sh
00-smoke-lib-sources.sh

# Lib-unit (commit 1) — call is_banned_scope / suggest_scope directly
10-banned-spec.sh
11-banned-plan.sh
12-banned-dotfiles.sh
13-banned-openspec.sh
14-good-component-not-banned.sh
20-suggest-package-dir.sh
21-suggest-superpowers-spec.sh
22-suggest-superpowers-plan.sh
23-suggest-openspec-changes.sh
24-suggest-docs-solutions.sh
25-suggest-multi-toplevel-empty.sh
50-sentinel-banned-list.sh

# Hook-integration (commit 2) — pipe PreToolUse JSON through git-safety.sh, grep emit
60-hook-smoke.sh
61-hook-emits-banned-warning.sh
62-hook-emits-suggest-from-spec-path.sh
63-hook-emits-atomicity-multi-toplevel.sh
64-hook-no-atomicity-single-toplevel.sh
65-hook-heredoc-skips-banned-check.sh
66-hook-single-quoted-msg-parsed.sh
67-hook-no-m-flag-skips.sh
```

Three test layers:

- **Lib unit** (IDs 00, 10-25, 50) — source `commit-scope.sh` directly, drive `is_banned_scope` + `suggest_scope` with fixture args, assert return code / stdout. Multi-toplevel case 25 asserts the lib returns empty (the atomicity warning itself is a hook concern).
- **Hook integration** (IDs 60-67) — `mktemp -d` git fixture, stage real files, synthesize PreToolUse JSON, pipe to `git-safety.sh`, grep stderr for expected emit substrings.
- **Sentinel** (ID 50) — assert `BANNED_SCOPES` array still contains `spec`, `plan`, `dotfiles`, `openspec`.

`run.sh` iterates `[0-9][0-9]-*.sh`, prints `PASS/FAIL`, exits non-zero on any fail. Same shape as `tests/read-once/run.sh`.

Coverage rule: each banned scope class in the CLAUDE.md anti-pattern table has a matching `1X-banned-*.sh` case. Each entry in `ARTIFACT_PREFIXES` has a matching `2X-suggest-*.sh` case.

## Data flow

```
agent issues:  git commit -m "docs(spec): foo"
        │
        ▼
PreToolUse hook fires (Bash matcher)
        │
        ▼
git-safety.sh:
  parse -m argument           → msg = "docs(spec): foo"
  extract declared_scope      → "spec"
  is_banned_scope "spec"      → true
  emit_context: "scope='spec' is BANNED ..."
        │
        ▼
(continues to staged-context emit:)
  collect staged files
  suggest_scope("...spec.md", "read-once,claude,codex") → "read-once"
  emit_context: "Staged files (1): ... Suggested scope: read-once ..."
        │
        ▼
agent sees both warnings before commit lands
```

## Error handling

- Missing lib file: hook hits `set -uo pipefail` source failure → fails loud, agent notices, lib must ship together with hook. Acceptable (atomic commit pairs lib + hook callers; doc commit lands separately but doesn't call lib).
- Malformed commit message (no `-m`, heredoc, mismatched quotes): banned-check skipped silently. Suggest + atomicity still emit on staged context.
- Empty staged list: existing hook returns at line 207-208 before any new code runs. Same behavior.
- Fresh repo (no `git log` history): `known_scopes` empty → `suggest_scope` returns empty → no false suggestion.
- Malformed lib array: sentinel test catches deletion of required entries.

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

1. `feat(claude): add commit-scope lib with banned + artifact prefix arrays`
   - `claude/.claude/lib/commit-scope.sh`
   - `claude/.claude/tests/commit-scope/{run.sh,helpers.sh}` + lib-unit cases 00, 10-14, 20-25, 50.
2. `feat(claude): wire commit-scope checks into git-safety hook`
   - `claude/.claude/hooks/git-safety.sh` extension (banned-check block + suggest/atomicity additions to staged-context emit).
   - Hook-integration test cases 60-67.
3. `docs(claude): document commit-scope rules in CLAUDE.md`
   - Replaces `### Commit rules` block in `claude/.claude/CLAUDE.md`.

Scope `claude` is correct on all three commits: lib + hook + doc all live under `claude/.claude/` and govern Claude-Code workflow. No multi-package staging.

## Out of scope

- Rewriting existing history. Prior convention doc handled that.
- Adding allow-list of known-good scopes (option C from brainstorming). Maintenance burden, rejected.
- Generated CLAUDE.md block from lib array (option B). Generation tooling overkill for ~10 strings.
- Env-var kill switch (`COMMIT_SCOPE_DISABLE`). Hook is warn-only; no need.
- Scope enforcement at push time. PreToolUse on Bash is sufficient.
- Coverage for non-conventional commit subjects (e.g., `Merge branch` lines). Scope regex `^[a-z]+\(([^)]+)\):` does not match merge lines; they skip the banned-scope check naturally.

## Success criteria

- `BANNED_SCOPES` array contains `spec`, `plan`, `dotfiles`, `openspec`, plus the rest of the table.
- `ARTIFACT_PREFIXES` array contains `docs/superpowers/specs`, `docs/superpowers/plans`, `docs/solutions`, `openspec/changes`.
- `bash claude/.claude/tests/commit-scope/run.sh` exits 0 with all cases PASS.
- A live commit attempt with `docs(spec): X` produces a visible PreToolUse warning citing `BANNED`.
- A live commit attempt with one file under `docs/superpowers/specs/2026-05-21-read-once-foo-design.md` produces a `Suggested scope: read-once` hint (given `read-once` exists in recent history).
- CLAUDE.md `### Commit rules` section renders the four subsections + anti-pattern table + canonical-list pointer + 5+5 examples.
- No new hook entries in `settings.json` (extending existing `git-safety.sh` PreToolUse registration).
