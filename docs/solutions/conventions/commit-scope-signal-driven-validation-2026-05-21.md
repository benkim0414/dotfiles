---
title: "Signal-driven commit-scope validation in PreToolUse hook"
date: 2026-05-21
category: conventions
module: claude-code-hooks
problem_type: convention
component: tooling
severity: medium
related_components:
  - development_workflow
  - documentation
applies_when:
  - "Writing a conventional-commits scope in a Claude Code hooked repo"
  - "Adding a new AI-skill framework or artifact directory under dotfiles"
  - "Reviewing or refactoring git-safety.sh / commit-scope.sh hook logic"
  - "Replacing hardcoded scope enum lists with signal-driven validation"
tags:
  - conventional-commits
  - commit-scope
  - git-hooks
  - pretooluse
  - signal-driven-validation
  - bash
  - repo-agnostic
  - dotfiles
---

# Signal-driven commit-scope validation in PreToolUse hook

## Context

In a dotfiles repo that hosts plan/spec artifacts under `docs/superpowers/specs/` and `docs/superpowers/plans/`, commits kept landing with scopes that named the artifact category (`docs(spec)`, `docs(plan)`) or the whole repo (`docs(dotfiles)`) instead of the actual component being changed. A history rewrite fixed the past (see [Use component scopes for Superpowers spec and plan commits](./superpowers-spec-plan-commit-scopes-2026-05-19.md)), but the underlying validation was a hand-maintained `BANNED_SCOPES` array plus an `ARTIFACT_PREFIXES` allow-list. Two problems surfaced:

1. Every new AI/skill framework (`openspec/`, `myskill/proposals/`, ...) introduced fresh artifact category names that bypassed the list until someone edited the lib.
2. Encoding framework names as literals in shared dotfiles tied the rule to specific tools — defeating the goal of a universal convention.

The team needed a scope check that works in any repo without per-framework or per-repo configuration.

This builds on the prior history-rewrite work and the "Atomic commits per review comment" practice (auto memory [claude]) — each signal and code-review fix was committed atomically during execution.

## Guidance

Validate commit scopes with **four signals derived at commit time**, not against a hand-curated list. Drive everything from filesystem conventions, the repo basename, staged file paths, and `git log -100` history.

**S1 — Universal container with history escape.** Reject if scope is a generic filesystem container AND has never been used as a scope before:

```bash
CONTAINER_NAMES=(docs doc src lib bin scripts script tests test \
  assets static public vendor build dist target packages apps)

is_container() {
  local s="$1" c
  for c in "${CONTAINER_NAMES[@]}"; do [[ "$s" == "$c" ]] && return 0; done
  return 1
}

is_in_history() {
  git log -100 --pretty=%s 2>/dev/null \
    | grep -qE "^[a-z]+\(${1}\):"
}
```

**S2 — Repo basename.** Reject if scope equals the repo directory name. Dynamically detected, no config:

```bash
repo_basename() { basename "$(git rev-parse --show-toplevel)"; }
```

**S3 — Path-segment match with history escape.** If the scope (or its `+s` plural) appears as a directory segment of any staged file AND is not in history, it is a category name, not a component:

```bash
_seg_matches_scope() {
  local scope="$1" seg="$2"
  [[ "$seg" == "$scope" ]] && return 0
  [[ "$seg" == "${scope}s" ]] && return 0   # spec -> specs, plan -> plans
  return 1
}
```

**S4 — New-scope soft advisory** (hook-only, never in the lib). When S1-S3 pass but the scope is absent from history and differs from a path-derived suggestion, emit a non-blocking hint via `emit_context`.

The lib (`commit-scope.sh`) exposes only `is_banned_scope` and `suggest_scope`. The hook parses `-m "..."` / `-m '...'`, extracts the scope from `^[a-z]+\(([^)]+)\):` (scoped form only — unscoped commits pass silently), and routes through `emit_context`. All warnings are non-blocking.

The "Plan artifacts in worktree" practice (auto memory [claude]) applied here: the spec, plan, and this resolution doc all live in the worktree and merge with the feature. The "Mechanical plan edits skip subagent" practice (auto memory [claude]) shaped execution — concrete code in the plan was applied via Edit directly rather than delegated.

### Bash gotcha

Bash 5 conditional-expression parser rejects unquoted regex with parenthesized capture groups:

```bash
# Errors: "syntax error in conditional expression: unexpected token `)'"
if [[ "$msg" =~ ^[a-z]+\(([^)]+)\): ]]; then ...
```

Assign the pattern to a variable first:

```bash
pat='^[a-z]+\(([^)]+)\):'
if [[ "$msg" =~ $pat ]]; then
  declared_scope="${BASH_REMATCH[1]}"
fi
```

## Why This Matters

A hand-curated banlist rots the moment a new framework adds an artifact directory. The signal-driven approach scales: any future tool that places artifacts under a category directory (`openspec/changes/`, `myskill/proposals/`, ...) is caught by S3 without lib changes, because path segments are computed per commit.

Repo basename detection (S2) eliminates per-repo configuration files. The same lib works in `dotfiles/`, `infra/`, `web-app/` — no fork, no overlay.

Using `git log -100` as the source of truth means the rule **learns from the team**. A legitimate new component scope earns its place after one commit; a bad scope keeps being flagged until corrected. No central registry to maintain.

Non-blocking warnings preserve trust. Engineers can override on intent (the soft advisory exists precisely for new components) without disabling the hook or fighting `--no-verify`.

Skipping this convention reintroduces the original failure: commits that name where the change is filed instead of what the change is, breaking scope-based changelog filtering and search.

## When to Apply

- Any repo that uses Conventional Commits with scopes.
- Repos hosting AI-skill, RFC, ADR, or spec artifacts under category directories.
- Multi-component repos where the basename or top-level dirs are tempting (but wrong) scope choices.
- Shared dotfiles or platform repos where a single hook serves many downstream projects.

Skip when the repo enforces unscoped Conventional Commits only — in that case the parser short-circuits and no signal fires.

## Examples

Assume a repo at `~/workspace/<repo-name>/` with a component directory `<component>/` and artifact paths like `docs/<framework>/specs/<component>-feature.md`.

**Good**

- `feat(<component>): add retry to upload pipeline` — scope names the actual component; appears in history after first land.
- `docs(<component>): document scope rules` — even when the change is under `docs/`, the scope is the component the docs describe.
- `chore(<component>-hooks): split git-safety into lib + hook` — sub-component scopes are fine; S3 only fires if the literal segment matches.

**Bad and how each signal catches it**

- `docs(docs): tweak readme` — S1 fires: `docs` is in `CONTAINER_NAMES` and (assume) not in history as a scope. Reject.
- `docs(<repo-name>): update top-level notes` — S2 fires: scope equals `basename $(git rev-parse --show-toplevel)`. Reject regardless of history.
- `docs(spec): add brainstorm output` with staged path `docs/<framework>/specs/<component>.md` — S3 fires: staged segment `specs` matches scope `spec` via the `+s` helper, and `spec` is not in history. Reject.
- `docs(proposals): file new RFC` with staged path `<framework>/proposals/0007.md` — S3 fires on the literal segment `proposals`. Reject. No lib change needed for a framework the author has never heard of.
- `feat(newthing): introduce module` when `newthing/` is freshly added and absent from history — S1-S3 pass; S4 emits a soft advisory: "Scope `newthing` not seen in last 100 commits; intended new component? Suggested from paths: `<derived>`." Non-blocking.

The bootstrap case (empty `git log`) is acknowledged: in a fresh repo the first commit for any new component trips S3 because there is no history to escape into. It settles within 2-3 commits and is locked by an integration test rather than papered over.

## Related

- [Use component scopes for Superpowers spec and plan commits](./superpowers-spec-plan-commit-scopes-2026-05-19.md) — the human-targeted convention this doc operationalises. The 2026-05-19 doc states the principle (prefer component scopes, avoid `spec`/`plan`/`<repo-name>`); this doc encodes the principle as automated signals in `claude/.claude/lib/commit-scope.sh` + `claude/.claude/hooks/git-safety.sh`. Both remain relevant: the human guidance applies when authors compose subjects; the automation catches drift before the commit lands.
- [Subagent-driven mechanical edit fidelity](../workflow-issues/subagent-driven-mechanical-edit-fidelity-2026-05-19.md) — execution practice used while implementing this feature.
