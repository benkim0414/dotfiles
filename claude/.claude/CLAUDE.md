# Global Claude Code Preferences

## Preferences

- Editor: nvim
- Never use emojis in responses
- IMPORTANT: Never assume -- if requirements are ambiguous, underspecified, or
  open to multiple interpretations, ask clarifying questions before proceeding.
  This applies to task scope, implementation approach, edge cases, naming, and
  any decision that could go more than one way.

## Response style

- Explain the reasoning behind config choices, not just what to set
- Present the dry-run/plan/diff form of a command before the apply form; let the user review first
- Use the fetch MCP to look up current docs, API versions, or package versions -- training data goes stale; never guess at versions

## Verification & context

- Always verify work before reporting completion -- run the project's test
  suite, linter, type checker, or build command. If none exist, describe what
  manual verification the user should perform.
- When an approach fails, prefer rewind (double-tap Esc) over inline
  correction -- rewinding drops the failed attempt from context.
- Use `/compact <hint>` to focus compaction (e.g., "focus on auth refactor,
  drop test debugging"). Use `/clear` with a written brief for new tasks.

## Semantic Search (qmd)

When qmd is available as an MCP server and the current project has an indexed
collection, prefer qmd `query` over Glob/Grep for finding relevant code.
qmd returns semantically ranked results, which is more effective for:
- Finding implementations by describing what they do (not what they're named)
- Discovering related code across a large codebase
- Answering "where is X handled?" questions

Fall back to Glob/Grep when:
- qmd is not available or the project has no indexed collection
- You need exact string/regex matches (import paths, error messages, symbol names)
- You need to find all occurrences exhaustively (refactoring, renaming)

Never automate `qmd collection add`, `qmd embed`, or `qmd update` --
indexing is always a manual user action.

## MCP servers (atlassian, qmd, sequential-thinking, slack)

These four `~/.claude.json` servers run as raw backends. An earlier
attempt to wrap them with `uvx mcp-compressor` (transform mode
`compressed-tools`) was reverted on 2026-05-22 because the compressor
advertises empty `inputSchema` for its dispatcher tools and Claude
Code's MCP client strips non-declared keys from `arguments` before
forwarding, so every required-arg call reached the backend with `{}`.
Symptom was a pydantic `Missing required argument [input_value={}]`
error from `mcp-atlassian`. Root cause is structural, not version-
specific. See
`docs/superpowers/specs/2026-05-22-atlassian-mcp-drop-compressor-design.md`
and
`docs/solutions/developer-experience/mcp-compressor-empty-schema-2026-05-22.md`.

The repo no longer carries the `mcp-add` wrapper helper. Add new MCP
servers with `claude mcp add --scope user <name> -- <command>`
directly.

## Git Workflow

All work happens on isolated worktree branches. Hooks enforce worktree
isolation, main-branch protection, and selective staging -- follow the
`[git-workflow]` context injection at session start.

`EnterWorktree` FIRST. All plan artifacts (brainstorm spec at
`docs/superpowers/specs/`, plan at `docs/superpowers/plans/`,
`ce-compound` solution doc at `docs/solutions/`) live inside the
worktree and merge with the feature.

### Canonical workflow

```
EnterWorktree
    ↓
brainstorming         (design + spec)
    ↓
writing-plans         (step-by-step plan)
    ↓
subagent-driven-development     (TDD + systematic-debugging inline)
    ↓
verification-before-completion
    ↓
requesting-code-review          (re-invoke after fixes until clean)
    ↓
ce-compound                     (capture learnings -> docs/solutions/)
    ↓
finishing-a-development-branch
   ├─ PR mode (default):    option 2 (push + gh pr create)
   │                        receiving-code-review (reactive on feedback)
   │                        user merges via gh pr merge --merge
   └─ no-pr mode (opt-in):  option 1 (local merge -> push main)
```

Full integration details: `~/.claude/docs/superpowers-workflow.md`

### Execution handoff after `writing-plans`

When `superpowers:writing-plans` finishes saving the plan and reaches its
"Execution Handoff" section, do NOT prompt the user with the "Which
approach?" question. Pick the most appropriate execution path yourself
and announce the choice in one line, then proceed.

Decision rule:

1. **Default:** `superpowers:subagent-driven-development` — the option
   the skill itself marks as recommended. Use this when tasks are
   meaningfully independent and dispatching subagents adds value.
2. **Exception — orchestrator-direct:** When the plan contains the
   exact final code and the tasks are mechanical edits (regex tweaks,
   single-block deletions, comment updates, line insertions),
   execute the edits inline from the orchestrator without dispatching
   subagents. This follows the existing
   `feedback_subagent_mechanical_edits` auto-memory; subagent
   round-trips on mechanical edits add latency and edit-fidelity
   risk without adding value.
3. **Exception — `superpowers:executing-plans`:** If you would
   otherwise have judged the inline-execution skill a better fit for
   the plan shape (e.g., tightly-coupled tasks that benefit from
   batched checkpoints rather than per-task review), invoke that
   instead.

Announce the chosen path in one line such as `Auto-invoking
subagent-driven-development per user preference.` or `Mechanical
edits — executing from orchestrator per feedback_subagent_mechanical_edits.`

Override: if the user explicitly names a different execution path in
the same turn (e.g. "use executing-plans for this one", "dispatch
subagents", "do it inline"), honour that request instead.

### Execution handoff for `ce-compound`

When `compound-engineering:ce-compound` reaches any interactive blocking
prompt, do NOT ask. Auto-select the recommended option, announce the choice
in one line, then proceed. Mirrors the `writing-plans` handoff above.
(Headless mode already skips these prompts -- this covers interactive runs.)

Prompt-by-prompt:

1. **Full vs Lightweight** -> always **Full**, the option the skill marks
   `(recommended)`.
2. **Session history** (Full only) -> the skill marks no recommendation, so
   pick per-run and state which. Default to **skipping** (the skill flags
   added time + token cost); opt in only when the documented problem clearly
   spans multiple prior sessions and that history would materially improve
   the doc.
3. **Discoverability Check consent** -> if the check finds a gap, apply the
   smallest fitting edit directly; if not, move on. No prompt either way.
4. **"What's next?" menu** -> auto-pick **only in no-pr repos**. Detect mode
   from the git-workflow session context / `CLAUDE_GIT_WORKFLOW=no-pr`.
   - **no-pr mode**: pick option 1 **Continue workflow** (skill-marked
     `(recommended)`) -> proceed to `finishing-a-development-branch`
     option 1 (local merge).
   - **PR mode (default)**: present the menu normally -- do NOT auto-select.
     Pushing + opening a PR is outward-facing; the user controls that step.

Announce in one line, e.g. `Auto-running ce-compound Full, skipping session
history, applying discoverability edit, continuing workflow per user
preference.` (drop the "continuing workflow" clause in PR-mode repos).

Override: if the user names a different choice in the same turn (e.g. "use
lightweight", "search session history", "stop after the doc"), honour that
instead.

### Commit rules

#### Atomicity

One commit = one self-contained logical change. Reviewable, bisectable,
revertable on its own. Heuristics for splitting:

- Subject contains "and" / "also" / "plus" -> split.
- Staged files span more than one top-level package or affect both code
  and unrelated docs -> split.
- Fixing a bug AND refactoring the surrounding code -> split (bug fix
  first, refactor second).
- Addressing multiple PR review comments -> one commit per comment.

#### Staging

- Stage specific files: `git add <path1> <path2>`.
- Never `git add -A`, `git add .`, `git add --all`, `git add --update`,
  `git commit -a`, `git commit -am`. Hook-enforced.

#### Conventional commits

- Form: `type(scope): description`.
- Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `perf`.

#### Scope = affected component, not artifact directory

Scope identifies WHAT the commit changes, not WHERE the artifact lives.
Read the file contents before choosing scope. The
`claude/.claude/hooks/git-safety.sh` hook emits a non-blocking warning
when the declared scope fails any of these signals (see
`claude/.claude/lib/commit-scope.sh` for the canonical implementation):

- **S1 - Universal container**: scope is a filesystem-convention
  container name (`docs`, `src`, `lib`, `bin`, `tests`, `scripts`,
  `packages`, `apps`, etc.) AND scope is not already in the repo's
  `git log` history.
- **S2 - Repo basename**: scope equals the current repository's
  directory name (e.g. scope `myapp` in repo `myapp/`). No history
  escape - repo names never identify a component.
- **S3 - Path-segment match**: scope (or its `+s` plural form) equals
  a directory segment of the staged file paths, AND scope is not in
  `git log` history. Catches `docs(spec)` when staging under
  `docs/superpowers/specs/`, `docs(openspec)` when staging under
  `openspec/changes/`, and any future framework that publishes to a
  documentation directory.
- **S4 - New-scope advisory** (soft): scope is allowed by S1-S3 but is
  not in `git log` history. Verify the scope names a component, not an
  artifact directory.

Real scopes are whatever component names appear in the current repo's
`git log`. Examples below use `<component>` placeholders; substitute
your repo's actual components.

#### Examples

```text
# Good
feat(<component>): <description>                 # scope names the affected component
docs(<component>): update <component> docs       # same
docs: <repo-wide policy change>                  # unscoped when no concrete component dominates

# Bad
feat(spec): <description>                        # 'spec' = artifact type (S3: matches 'specs/' segment)
feat(plan): <description>                        # 'plan' = artifact type (S3: matches 'plans/' segment)
docs(<repo-name>): <description>                 # repo name = location (S2)
docs(openspec): <description>                    # framework name (S3: matches 'openspec/' segment)
docs(docs): <description>                        # universal container (S1)
feat(<component>): change X and Y                # "and" = two changes -> split
```

### PR mode (default)

After implementation + `requesting-code-review` is clean +
`ce-compound` has documented the solution: invoke
`finishing-a-development-branch`, pick option 2 (push +
`gh pr create`). The skill pushes the feature branch and opens the PR.

After PR creation:

- External reviewer feedback (if any) -> `receiving-code-review` ->
  fix -> push -> loop until clean.
- No external review -> proceed to merge.

Merge:

- YOU MUST use merge commits: `gh pr merge --merge`. Never squash,
  never rebase.
- After merge: `ExitWorktree("keep")` to return to main.

### No-pr mode (opt-in)

Enable per repo by setting
`"env": {"CLAUDE_GIT_WORKFLOW": "no-pr"}` in that repo's
`.claude/settings.local.json`. The hook reads the env var; no other
config required. This dotfiles repo is the documented example.

After implementation + `requesting-code-review` is clean +
`ce-compound` has documented the solution: invoke
`finishing-a-development-branch`, pick option 1 (local merge). Then
push main. No PR created.

### Worktree exit

- `ExitWorktree("keep")` after merge (default).
- `ExitWorktree("remove")` only for exploratory work with no commits.

## Plugin integration

`superpowers@superpowers-marketplace` and
`compound-engineering@compound-engineering-plugin` are both enabled.
Skill chain documented above.

Caveats:

- Worktree management uses the harness `EnterWorktree` / `ExitWorktree`
  tools (hook-enforced) -- NOT `superpowers:using-git-worktrees`.
- Parallel agents: use `caveman:cavecrew` for compressed delegation
  when context budget matters; use
  `superpowers:dispatching-parallel-agents` for the standard parallel
  pattern.
- Skill authoring: use the separate `skill-creator` plugin if needed.
