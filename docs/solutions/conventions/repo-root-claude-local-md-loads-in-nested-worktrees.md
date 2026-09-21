---
title: A repo-root CLAUDE.local.md loads in nested .claude/worktrees sessions
date: 2026-09-21
category: conventions
module: claude-code-config
problem_type: convention
component: tooling
severity: medium
applies_when:
  - Keeping personal Claude Code instructions in a repo shared with coworkers
  - Starting a session inside <repo>/.claude/worktrees/<name>/ created by the EnterWorktree tool
  - Choosing between a repo-root CLAUDE.local.md and the home-directory import the official docs recommend
  - Ignoring an untracked personal file without editing a shared .gitignore
  - Adding a CLAUDE.local.md to a repo whose instructions live in AGENTS.md
tags:
  - claude-local-md
  - claude-md
  - worktrees
  - memory-resolution
  - enterworktree
  - git-info-exclude
  - agents-md
  - claude-code-config
---

# A repo-root CLAUDE.local.md loads in nested .claude/worktrees sessions

## Context

Claude Code's memory documentation warns that `CLAUDE.local.md` does not travel
across worktrees:

> If you work across multiple git worktrees of the same repository, a
> gitignored `CLAUDE.local.md` only exists in the worktree where you created
> it. To share personal instructions across worktrees, import a file from your
> home directory instead: `@~/.claude/my-project-instructions.md`.

That warning arrived at exactly the wrong moment. The
`worktree-global-config-trim` branch reduced the per-user global
`claude/.claude/CLAUDE.md` (stowed to `~/.claude/CLAUDE.md`) from 297 lines to
11 carrying only commit rules, so each project could declare the workflow its
characteristics call for. The superpowers/compound-engineering chain that used
to live there had to land somewhere per-project, and the target was
`~/workspace/ops/CLAUDE.local.md` — untracked and personal, in a repo shared
with coworkers whose `AGENTS.md` is the team contract. `ops` currently has 28
linked worktrees (`git worktree list` prints 29 lines, the main checkout plus
28). Taken at face value, the warning says that approach needs the
home-directory indirection, which costs a one-time external-import approval
dialog per project.

**The warning assumes worktrees are siblings of the repo.** That is what
`git worktree add ../feature-x` produces, and for that layout the warning is
correct: the upward walk from `../feature-x` never passes through the repo
root. But the same documentation says Claude Code loads `CLAUDE.md` and
`CLAUDE.local.md` from the current working directory and every directory above
it, and describes no git-boundary stop in that walk. The Claude Code harness
`EnterWorktree` tool places worktrees at `<repo>/.claude/worktrees/<name>/` —
*inside* the repo — so the walk up from a worktree passes through `<repo>/` and
picks up `<repo>/CLAUDE.local.md` on the way. One file covers every worktree,
with no import and no dialog.

This session verified that rather than assuming it. A sentinel line was placed
in the file and read back from both locations:

```sh
cd ~/workspace/ops && \
  claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."
cd ~/workspace/ops/.claude/worktrees/infra-592-baseline && \
  claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."
```

Both returned `loaded-ok`. The sentinel was then removed; the file today is 92
lines and contains no occurrence of it.

**The method is strong evidence, not proof.** Echoing a sentinel cannot
distinguish "loaded as an instruction" from "the agent noticed an
obviously-named file in the working directory and read it with a tool". That is
the exact failure this repo already documents in
`docs/solutions/conventions/assertions-that-pass-when-they-cannot-check-2026-09-18.md`:
an assertion whose passing branch means two things. The decisive version adds
an absence control — move the file aside, assert `NONE`, restore it, then
assert the sentinel — and it was not run. Treat the result as it is recorded in
`docs/superpowers/specs/2026-09-21-global-config-trim-design.md:196` (V1),
which states the caveat alongside the outcome.

## Guidance

**Check where your worktrees actually live before believing the warning.** If
`git worktree list` shows paths under `<repo>/`, a repo-root `CLAUDE.local.md`
reaches all of them and the home-directory import is unnecessary indirection.
If it shows sibling paths, the warning applies and the import is the fix.

**Ignore the file through `.git/info/exclude`, not `.gitignore`.** `.gitignore`
is committed and shared; in a coworker's repo, adding a personal filename to it
is a shared change that has to be justified in review. `info/exclude` lives in
the common git directory, which linked worktrees share, so one entry covers
every worktree and leaves no diff in a tracked file. Add the entry *before*
creating the file, so it is never briefly visible in `git status` in a shared
repo. This repo already uses the same mechanism for the same reason in
`docs/solutions/conventions/install-git-hooks-under-husky-core-hookspath.md`,
which keeps a machine-local hook out of a shared tracked tree by writing to the
common directory's `info/exclude`.

**`info/exclude` does not protect the file from `git clean -x`.** An ignored
file is exactly what `clean -x` removes. In `ops`, an Nx monorepo where
`git clean -fdx` is a routine reset, a machine-local file with no copy anywhere
is one reset away from gone. This was accepted as a known cost on this branch
(`docs/superpowers/specs/2026-09-21-global-config-trim-design.md:273`), not
solved. If the content matters, keep the body at
`~/.claude/<project>-workflow.md` and make the repo file a one-line import —
the layout the fallback in
`docs/superpowers/plans/2026-09-21-global-config-trim.md:471` (Task 3, Step 7)
describes. That survives `clean -fdx` and costs the approval dialog.

**Check for `AGENTS.md` without `CLAUDE.md` before dropping the file in.** Per
the same Claude Code documentation, `AGENTS.md` is read by default only when
there is no `CLAUDE.md` or `CLAUDE.local.md` in the working directory or above
it. In `ops` this is harmless: `CLAUDE.md` is a symlink to `AGENTS.md`, so the
local file is purely additive. In a repo that has `AGENTS.md` and no
`CLAUDE.md`, adding a `CLAUDE.local.md` silently stops the team contract
loading — no warning, no error, and the only symptom is an agent that has
stopped following conventions nobody thinks to re-check.

## Why This Matters

The blocker was documentation read without its assumption. The warning is true
for the layout git gives you by default and false for the layout the harness
gives you, and nothing in the sentence says which it is describing. Accepting
it unexamined would have bought an unnecessary import stub and an approval
dialog in every project, permanently, to solve a problem that does not exist in
this setup — and the indirection would then have been copied to the next repo,
and the next, as established practice.

The two adjacent facts carry the same shape. `info/exclude` versus `.gitignore`
looks like a stylistic preference until you are in someone else's repo, where
one of them is a shared change and the other is not. The `AGENTS.md`
suppression is invisible by construction: the failure is a file that stops being
read, which produces no output at all. Both are cheap to get right on the way
in and expensive to notice later.

**One cost this pattern does not avoid, stated plainly because an existing
learning argues the other way.**
`docs/solutions/workflow-issues/encode-workflow-preferences-via-claude-md-2026-05-26.md`
holds that instruction files are the durable home for workflow preferences
precisely because they travel with the dotfiles repo and reproduce on a new
machine. An untracked `CLAUDE.local.md` fails that test by construction: it is
not version-controlled, not backed up, and absent on the next clone. The
worktree finding above removes one objection to the pattern; it does not remove
that one, which was accepted deliberately on this branch rather than solved.
The import layout under `git clean -x` above is the variant that keeps both
properties.

## When to Apply

- Placing personal, untracked instructions in a repo that has worktrees, before
  reaching for `@~/.claude/...` on the strength of the docs warning.
- Adding any personal file to a repo shared with coworkers, when deciding
  between `.gitignore` and `.git/info/exclude`.
- Repeating this pattern in a second repo — re-check the `AGENTS.md` precondition
  per repo; it is not a property of the pattern, it is a property of the target.
- Any repo where `git clean -fdx` is part of the normal reset loop, and the
  ignored file's content is not reproducible from anywhere else.

Not applicable when worktrees are siblings of the repo (`git worktree add ../x`)
— there the documented home-directory import is the correct answer.

## Examples

Establish the layout first. Worktree paths under the repo root mean the walk
reaches a repo-root `CLAUDE.local.md`:

```sh
cd ~/workspace/ops && git worktree list
# /Users/ben/workspace/ops                                        <sha> [main]
# /Users/ben/workspace/ops/.claude/worktrees/infra-592-baseline   <sha> [...]
```

Ignore before creating, then confirm both halves of the claim — that git cannot
see the file, and that the ignore came from `info/exclude` rather than a shared
file:

```sh
printf 'CLAUDE.local.md\n' >> ~/workspace/ops/.git/info/exclude
# ... write the file ...
cd ~/workspace/ops
git status --porcelain | grep CLAUDE.local.md    # no output
git check-ignore -v CLAUDE.local.md
# .git/info/exclude:20:CLAUDE.local.md	CLAUDE.local.md
```

Verified on 2026-09-21: `git status --porcelain` in `ops` was empty, the
check-ignore hit is `.git/info/exclude:20`, and `.gitignore` contains no
`CLAUDE` entry.

Check the `AGENTS.md` precondition before writing anything:

```sh
ls -la ~/workspace/ops/CLAUDE.md
# ...  CLAUDE.md -> AGENTS.md      <- symlink, so CLAUDE.local.md is additive
```

A bare `AGENTS.md` with no `CLAUDE.md` beside it is the case to stop on.

Verify loading with an absence control, which is the part this session skipped:

```sh
# 1. absence control — expect NONE
mv CLAUDE.local.md /tmp/CLAUDE.local.md.bak
claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."

# 2. restore and re-run from the repo root and from a linked worktree — expect the sentinel
mv /tmp/CLAUDE.local.md.bak CLAUDE.local.md
claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."
cd .claude/worktrees/<name> && \
  claude -p "Reply with only the value of PERSONAL_WORKFLOW_SENTINEL from your instructions, or NONE."
```

Without step 1, a passing step 2 is consistent with the agent having read the
file as a file rather than loaded it as an instruction.

The primary record for this change is
`docs/superpowers/specs/2026-09-21-global-config-trim-design.md` — D2
(line 51, why the text lives in `ops/CLAUDE.local.md`), D3 (line 70,
`info/exclude` over `.gitignore`), and V1 (line 196, the worktree-loading
verification and its caveat) — with the executable form in
`docs/superpowers/plans/2026-09-21-global-config-trim.md:283` (Task 3). Both
live on the unmerged `worktree-global-config-trim` branch as of writing.

## Related

- [Company vs personal Claude config layering](../architecture-patterns/company-vs-personal-claude-config-layering-2026-06-19.md) — the closest prior art on where instruction text lives and how it reaches a session. Its permission half still holds; its `@CLAUDE.company.md` import guidance is contradicted by the same branch that produced this doc, which stopped the global importing that file.
- [Encode workflow preferences via CLAUDE.md](../workflow-issues/encode-workflow-preferences-via-claude-md-2026-05-26.md) — argues instruction files are durable because they reproduce on a new machine. See the reproducibility paragraph above for where this pattern diverges.
- [Install git hooks under husky core.hooksPath](install-git-hooks-under-husky-core-hookspath.md) — in-repo precedent for keeping a machine-local file out of a shared tracked tree via the common directory's `info/exclude`.
- [Assertions that pass when they cannot check](assertions-that-pass-when-they-cannot-check-2026-09-18.md) — why the sentinel test needs an absence control before its passing branch means anything.
- [Enforce Codex workflows in linked worktrees](../workflow-issues/enforce-codex-workflows-in-linked-worktrees-2026-05-20.md) — the enforcement-side companion: config scoped to linked worktrees, from the hook rather than the memory-file angle.
- [Default subagent-driven superpowers execution](default-subagent-driven-superpowers-execution.md) — encodes its default in `codex/.codex/AGENTS.md`, so the `AGENTS.md`-suppression precondition above applies directly if that repo ever gains a `CLAUDE.local.md`.
