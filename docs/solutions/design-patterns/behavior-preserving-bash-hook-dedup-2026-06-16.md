---
title: "Behavior-preserving dedup of Bash hook logic into shared lib helpers"
date: 2026-06-16
category: design-patterns
module: dotfiles/claude
problem_type: design_pattern
component: tooling
severity: medium
applies_when:
  - "Extracting duplicated logic from multiple Claude Code hooks into a claude/.claude/lib/ helper"
  - "A hook has a hot path that must avoid sourcing libs but also a cold error path that wants shared logic"
  - "Detecting linked-vs-main git worktree in Bash, or comparing git-dir paths"
  - "A shell test fixture under macOS /var (mktemp) compares paths and spuriously fails"
related_components:
  - development_workflow
  - testing_framework
tags:
  - hooks
  - bash
  - dedup
  - worktree
  - symlink
  - lazy-source
  - refactor
  - git-safety
---

# Behavior-preserving dedup of Bash hook logic into shared lib helpers

## Context

The Claude Code hooks under `claude/.claude/hooks/` had accumulated three copy-pasted
logic blocks: the deleted-CWD `repo_hint` regex (4 hooks), the linked-vs-main worktree
detection (2 hooks), and the `CLAUDE_GIT_WORKFLOW == "no-pr"` gate (4 hooks). Extracting
these into `claude/.claude/lib/session.sh` helpers (`cwd_repo_hint`, `worktree_kind`,
`workflow_no_pr`) is a behavior-preserving refactor — but three non-obvious pitfalls turn
"obviously safe" dedup into something that can change behavior or break tests. This doc
captures the discipline and the two concrete gotchas.

## Guidance

### 1. Reproduce existing behavior exactly; defer hardening to a separate commit

When extracting an inline block into a helper, the helper must be functionally identical
to the code it replaces — even where the original is suboptimal. If you spot a latent
edge-case bug while extracting, do NOT fix it in the same change. Land the
behavior-preserving extraction first (guarded by tests that prove equivalence), then fix
the edge case in a dedicated follow-up commit with its own test. Folding a behavior change
into a "refactor" defeats bisectability and hides the change from review.

### 2. Bash worktree detection is fragile to symlinked parent paths

The idiomatic linked-vs-main check compares git's `--absolute-git-dir` (physically
resolved) against a logicalized `--git-common-dir`:

```bash
worktree_kind() {
  git rev-parse --git-dir >/dev/null 2>&1 || { printf 'none'; return; }
  [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && { printf 'none'; return; }
  local abs common
  abs=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
  common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
  if [[ -n "$abs" && -n "$common" && "$abs" != "$common" ]]; then
    printf 'linked'   # linked worktree: git-dir lives under <main>/.git/worktrees/<name>
  else
    printf 'main'
  fi
}
```

`--absolute-git-dir` is physically resolved by git, but `cd "$dir" && pwd` returns the
**logical** path (no symlink resolution). When the repo is reached through a symlinked
parent (e.g. a repo under `/tmp` → `/private/tmp`, or a home dir symlinked through `/var`),
the two strings differ and a **main** tree is misreported as **linked**. This is latent,
not theoretical — it surfaced immediately in tests (see gotcha 3).

In production the dotfiles worktree workflow lives under a non-symlinked
`~/workspace/dotfiles/...`, so the bug does not bite, and it is identical to the
pre-refactor inline behavior — hence kept as-is. If you ever need to harden it, resolve
both sides physically (`pwd -P`) in a separate commit with a symlinked-parent test.

### 3. macOS `mktemp` test fixtures need `pwd -P`

`mktemp -d` on macOS returns a path under `/var/folders/...`, and `/var` is a symlink to
`/private/var`. A test that creates a git repo there and calls `worktree_kind` (gotcha 2)
will get `linked` for a main repo because git resolves `/private/var` while the fixture's
logical path stays `/var`. Pin the temp root to its physical path so the comparison is
honest — without altering the helper under test:

```bash
CASE_TMP="$(cd "$(mktemp -d -t my-test.XXXXXX)" && pwd -P)"
```

### 4. Lazy-source a shared lib only in a hook's cold branch

`git-safety.sh` deliberately sources no lib on its hot path (~90% of Bash tool calls are
non-git, fast-exited before any `source`). To let it use a shared helper without
regressing that, source the lib **inside the cold error branch** that needs it:

```bash
if [[ ! -d "$PWD" ]]; then
  # Cold path (deleted CWD): lazily source session.sh for cwd_repo_hint so the
  # hot path (~90% of Bash calls) stays lib-free.
  # shellcheck source=../lib/session.sh
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"
  repo_hint=$(cwd_repo_hint)
  ...
fi
```

Hooks that already source the lib at top (e.g. `git-session-start.sh`,
`restore-git-context.sh`) just call the helper directly. Leave an inline copy with a
pointer comment in the hot-path hook for gates too trivial to justify a cold-branch source
(e.g. `git-safety.sh` keeps its inline `CLAUDE_GIT_WORKFLOW` check, commenting that
`workflow_no_pr` in the lib is canonical).

## Why This Matters

A "pure refactor" that silently changes an edge case is the worst kind of regression: it
sails through review because the diff looks mechanical. Keeping extraction
behavior-identical and pushing fixes to follow-ups preserves bisectability and keeps review
honest. The worktree/symlink and `mktemp` gotchas are easy to misdiagnose as "the helper is
broken" when the helper is in fact faithful — recognizing them saves a debugging loop and
prevents a spurious "fix" that changes production behavior. The lazy-source pattern lets a
performance-sensitive hook share code without paying the per-call cost of sourcing a lib on
its hot path.

## When to Apply

- Extracting any duplicated block from multiple hooks into a `lib/` helper.
- Writing or reviewing a Bash worktree/git-dir comparison.
- A shell test that builds a git repo in a temp dir and compares paths fails only on macOS.
- A hook needs shared logic but has a documented hot-path-stays-lib-free constraint.

## Examples

Behavior-preserving extraction, adopted four ways (the `repo_hint` regex):

```bash
# lib/session.sh
cwd_repo_hint() {
  if [[ "$PWD" =~ ^(.*)/\.claude/worktrees/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# hooks that source the lib at top -> direct call:
repo_hint=$(cwd_repo_hint)
```

Verifying equivalence rather than asserting it: each helper got a test case with a
positive assertion (`worktree_kind` in a real `git worktree add` tree returns `linked`),
and the existing suites that exercise the touched hooks (`commit-scope` covers
`git-safety.sh`, `permission-policy` covers `permission-policy.sh`) were kept green across
every commit.

## Related

- `docs/solutions/conventions/commit-scope-signal-driven-validation-2026-05-21.md` — sibling
  hook+lib split (`git-safety.sh` + `commit-scope.sh`); same refactor space, different concern.
- `docs/solutions/documentation-gaps/env-driven-default-doc-drift-2026-05-22.md` — documents the
  `CLAUDE_GIT_WORKFLOW`/`no-pr` gate across four hooks; its "four inline gates" description is now
  partially stale since `workflow_no_pr` centralizes the gate (git-safety.sh keeps an inline copy by design).
- `docs/superpowers/specs/2026-06-16-claude-hooks-cleanup-dedup-design.md` — the design spec.
- `docs/superpowers/plans/2026-06-16-claude-hooks-cleanup-dedup.md` — the implementation plan.
