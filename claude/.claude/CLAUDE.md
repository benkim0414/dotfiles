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

## MCP servers wrapped by mcp-compressor

Four servers in `~/.claude.json` (atlassian, qmd, sequential-thinking,
slack) are proxied through `uvx mcp-compressor`. The compressor exposes
only two dispatcher tools per server -- `<server>_get_tool_schema` and
`<server>_invoke_tool` -- with an empty advertised inputSchema. The
schema is wrong; the dispatcher actually requires arguments.

To call any tool on these servers, supply the dispatcher args
explicitly:

- `<server>_get_tool_schema(tool_name="real_tool_name")` -- returns the
  real input schema for that backend tool.
- `<server>_invoke_tool(tool_name="real_tool_name", arguments={...})`
  -- invokes it. `arguments` is an inline object, NOT a JSON string,
  NOT flat keys at the dispatcher level, NOT `params` / `kwargs` /
  `input` / `name`.

The list of real tools available behind each dispatcher is in the
dispatcher's own tool description (`Available tools are: <tool>...`).
Read the description before the first call; do not probe arg shapes.

If a call returns `-32602 missing tool_name`, you forgot `tool_name` --
the empty inputSchema is misleading you. Pass `tool_name` even though
it is not declared.

### Version pin

`mcp-add` pins `mcp-compressor` to 0.22.0 via
`uvx --from mcp-compressor==0.22.0`. 0.23.0 (PyPI 2026-05-21) regressed
required-argument passthrough in `compressed-tools` mode - the backend
receives `input_value={}` and rejects every call carrying required
arguments. Reproduced against `mcp-atlassian` (`jira_get_issue`,
`jira_get_user_profile`) on 2026-05-22.

To test a newer release without editing `mcp-add`:

```sh
MCP_COMPRESSOR_VERSION=0.24.0 mcp-add <name> -- <cmd>
```

To bump the default after upstream fixes the regression, change the
constant in `bin/.local/bin/mcp-add` and re-run the regeneration
procedure documented in
`docs/superpowers/specs/2026-05-22-atlassian-mcp-fix-design.md`.

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
