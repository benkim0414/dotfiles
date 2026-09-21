# Trim the global CLAUDE.md to commit rules

Date: 2026-09-21
Status: approved

## Goal

Reduce `claude/.claude/CLAUDE.md` from 297 lines to commit rules only, and
relocate the superpowers/compound-engineering workflow into per-project
config so each repo can run the workflow its characteristics call for.

The ops repo is the first project to receive its own workflow config. Other
repos are handled separately, later.

## Problem

`claude/.claude/CLAUDE.md` accumulated four kinds of content that do not
belong in a per-user global file:

1. **Project-specific workflow.** The canonical superpowers chain, the
   `writing-plans` execution handoff, and the `ce-compound` execution handoff
   describe one way of working. Applying them in every repo prevents the
   flexible per-project workflow this change is meant to enable.
2. **Repo history.** The `mcp-compressor` post-mortem (L52-69) records why a
   wrapper was dropped from this dotfiles repo. It already has a
   `docs/solutions/` doc and changes no agent behaviour.
3. **Hook documentation.** The commit-scope S1-S4 signals (L201-245, 45 lines)
   document `claude/.claude/lib/commit-scope.sh`, which lives in this repo and
   already emits the warning at runtime.
4. **Stale or inapplicable advice.** The "use the fetch MCP" bullet names a
   server that is not configured. The rewind-via-Esc and `/compact` bullets
   describe actions the user takes, not actions an agent can take.

## Decisions

### D1 — Global keeps commit rules only

Everything else is removed, including the `CLAUDE.company.md` import, the
Preferences block, and the qmd section. Rationale: the user wants the global
file to carry only what is universal and load-bearing in every repo.

Consequence, accepted: the never-assume rule survives only as auto-memory
(`feedback_never_assume`), which is weaker than a CLAUDE.md instruction, and
the company wiki-query directive goes dormant until re-imported per project.

### D2 — Workflow lives in `ops/CLAUDE.local.md`, untracked

Rejected: `ops/AGENTS.md`. It is a cross-tool contract shared with coworkers
and read by six other agent tools. Adding a personal plugin chain there
reverses the 2026-05-26 personal-preference-bleed decision that stripped the
`benkim0414` assignee line for exactly this reason.

Rejected: content in dotfiles with a thin importing stub in ops. Offered and
declined. It would keep the text version-controlled and cross-device, at the
cost of one external-import approval dialog per repo.

Chosen: the full text sits in `ops/CLAUDE.local.md`. `CLAUDE.local.md` is the
documented "Local instructions" scope — personal, gitignored, loaded last at
its level so it wins ties.

Accepted cost: the text exists only on this machine. It is not backed up, not
reproducible on a new clone or device, and diverges from how the rest of this
config is managed.

### D3 — Ignore via `.git/info/exclude`, not `.gitignore`

`ops/.gitignore` is committed and shared. `info/exclude` lives in the common
git directory, so it applies to every linked worktree and leaves no
shared-file change in a repo coworkers use.

### D4 — Commit-scope S1-S4 moves to `dotfiles/CLAUDE.md`

This repo owns `commit-scope.sh` and `git-safety.sh`, so documenting their
signals here is a delta, not a restatement of the global. Other repos keep the
hook's runtime warning; `ops/AGENTS.md` already states its own scope rule with
real service names.

### D5 — Hooks are untouched

Deleting the hook layer and adopting `git-guardrails-claude-code` is a
separate change, deferred to its own brainstorm. Recorded here because it
constrains what this change may assume.

Findings that the follow-up must resolve:

- The guardrails script is a hook itself, so "remove all hooks" means
  "replace 14 hand-written hooks with one third-party hook".
- It blocks `git push` outright with no allowlist and no bypass. Both PR mode
  (push the feature branch) and no-pr mode (push main after local merge)
  require a push, so it would block the normal path in every repo.
- Its nine patterns overlap only `git-safety.sh`, and only partly. It does not
  cover worktree isolation, main-branch protection, the `git add -A` ban,
  commit-scope warnings, or the semantic permission policy.
- `codex/.codex/config.base.toml` registers the same scripts and would break
  independently.

This change depends on the hooks continuing to work. In particular
`git-session-start.sh` gates its superpowers chain injection behind
`workflow_no_pr`, which is what keeps `dotfiles`, `wiki`, and `hermes-agent`
working after the global text is removed.

## Changes

### 1. `claude/.claude/CLAUDE.md` — replace entirely

Final contents, 13 lines:

```markdown
# Commit rules

One commit = one logical change. Split when the subject needs "and",
when staged files span unrelated areas, or when a fix and a refactor
are mixed.

Stage explicit paths: `git add <path>`. Never `-A`, `.`, `--all`,
`--update`, `git commit -a`, `git commit -am`.

Form: `type(scope): description`. Types: feat, fix, docs, chore,
refactor, test, ci, perf.
```

No heading framing, no "Hook-enforced" note — the hook enforces it whether or
not the file says so.

### 2. `CLAUDE.md` (dotfiles project file) — add commit-scope section

Move L201-245 of the old global verbatim, as a new section documenting the
`git-safety.sh` scope warning and the S1-S4 signals.

### 3. `~/workspace/ops/CLAUDE.local.md` — create, untracked

Sections, adapted to ops being a PR-mode repo:

- Canonical workflow chain, PR-mode variant ending in
  `finishing-a-development-branch` option 2 and `gh pr merge --merge`.
- Artifact placement: `docs/superpowers/specs/`, `docs/superpowers/plans/`,
  `docs/solutions/`, all inside the worktree.
- Execution handoff after `writing-plans` (old global L108-140).
- Execution handoff for `ce-compound` (old global L142-174), keeping only the
  PR-mode branch: present the "What's next?" menu, do not auto-select.
- PR mode rules: merge commits only, never squash, never rebase.
- Worktree exit: `ExitWorktree("keep")` after merge.
- Plugin caveats: use the harness `EnterWorktree`/`ExitWorktree`, not
  `superpowers:using-git-worktrees`; `caveman:cavecrew` for compressed
  delegation, `superpowers:dispatching-parallel-agents` otherwise.

### 4. `~/workspace/ops/.git/info/exclude` — add `CLAUDE.local.md`

## Removed from global

| Section | Old lines | Destination |
|---|---|---|
| Company configuration import | 3-8 | Deleted; `CLAUDE.company.md` stays on disk, unreferenced |
| Preferences | 10-17 | Deleted |
| Response style | 19-23 | Deleted; the fetch-MCP bullet was stale regardless |
| Verification & context | 25-33 | Deleted; rewind and `/compact` are user actions |
| Semantic Search (qmd) | 35-50 | Deleted |
| MCP servers post-mortem | 52-69 | Deleted; already in `docs/solutions/` |
| Git Workflow prose | 71-81 | Deleted; `git-session-start.sh` injects the worktree rule |
| Canonical workflow diagram | 82-106 | `ops/CLAUDE.local.md` |
| Execution handoff: `writing-plans` | 108-140 | `ops/CLAUDE.local.md` |
| Execution handoff: `ce-compound` | 142-174 | `ops/CLAUDE.local.md` |
| Commit rules | 176-199 | Kept, rewritten terse |
| Commit scope S1-S4 | 201-245 | `CLAUDE.md` (dotfiles project file) |
| PR mode | 247-264 | `ops/CLAUDE.local.md` |
| No-pr mode | 266-276 | Deleted; the hook already states the mode |
| Worktree exit | 278-281 | `ops/CLAUDE.local.md` |
| Plugin integration | 283-297 | `ops/CLAUDE.local.md`, caveats only |

`~/.claude/docs/superpowers-workflow.md` is unchanged. Both
`git-session-start.sh:161` and `restore-git-context.sh:53` reference it in
no-pr mode.

## Verification

### V1 — `CLAUDE.local.md` reaches linked worktrees (blocking)

Claude Code loads `CLAUDE.md` and `CLAUDE.local.md` from the working directory
and every directory above it. The ops worktrees sit at
`ops/.claude/worktrees/<name>/`, inside the repo, so the upward walk should
reach `ops/CLAUDE.local.md`. The docs describe no git-boundary stop, but this
is reasoned from the documented resolution order and has not been run.

Test with a sentinel line in the file:

```sh
cd ~/workspace/ops && \
  claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."
cd ~/workspace/ops/.claude/worktrees/infra-592-baseline && \
  claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."
```

Both must return the sentinel. If the worktree run returns `NONE`, fall back
to the documented home-directory import: put the workflow at
`~/.claude/ops-workflow.md` and make `ops/CLAUDE.local.md` a stub that imports
it. That costs one external-import approval dialog.

Remove the sentinel line once both runs pass.

### V2 — the file is not stageable in ops

```sh
cd ~/workspace/ops && git status --porcelain | grep CLAUDE.local.md
git check-ignore -v CLAUDE.local.md
```

First command returns nothing. Second names `.git/info/exclude`.

### V3 — dotfiles suites still pass

```sh
bash claude/.claude/tests/commit-scope/run.sh
bash claude/.claude/tests/output-style/run.sh
bash bin/tests/stow-hygiene/run.sh
```

### V4 — no dangling references to removed sections

```sh
grep -rn "Execution handoff\|Canonical workflow\|CLAUDE.company" \
  --include="*.md" --include="*.sh" . | grep -v docs/solutions | grep -v docs/superpowers
```

Every remaining hit must be intentional.

### V5 — the stowed symlink still resolves

```sh
readlink ~/.claude/CLAUDE.md && head -1 ~/.claude/CLAUDE.md
```

Must print `# Commit rules`. The symlink points at the main checkout, so this
only passes after merge.

## Risks

| Risk | Mitigation |
|---|---|
| `CLAUDE.local.md` does not load in worktrees | V1 is blocking; home-directory import is the fallback |
| Workflow text lives only on this laptop | Accepted by the user; no mitigation |
| never-assume degrades to auto-memory only | Accepted; re-add per project if adherence drops |
| Wiki-query directive dormant everywhere | `CLAUDE.company.md` is kept on disk for per-project reuse |
| No-pr repos lose the execution handoffs | Their chain still comes from `git-session-start.sh`; handoffs return with their project config |
| Service repos lose commit-scope guidance | `git-safety.sh` still warns at runtime |

## Out of scope

- Removing hooks and adopting `git-guardrails-claude-code`. See D5.
- Project config for `dotfiles`, `wiki`, `hermes-agent`, and the service repos.
- Deleting `CLAUDE.company.md`.
- Rotating the GitHub PAT embedded in the `ops` origin remote URL, noticed
  during exploration. Unrelated to this change and worth doing.
