# Global Codex Preferences

## Core Behavior

- Never use emojis in responses.
- Ask clarifying questions before proceeding when requirements are ambiguous,
  underspecified, or open to multiple reasonable interpretations. This applies
  to task scope, implementation approach, edge cases, naming, and tradeoffs.
- Explain the reasoning behind config choices, not just what to set.
- Present the dry-run, plan, or diff form of a command before the apply form;
  let the user review first.
- Use web search for current docs, API versions, package versions, image
  digests, chart versions, and other time-sensitive facts. Never guess at
  versions from training data.
- Default editor is `nvim`. Do not open VS Code or other GUI editors.

## Session Start

- At the beginning of every session, run `git status` and `git branch` to
  establish context.
- Report the current branch and working tree state.
- If on `main` with uncommitted work, warn immediately before doing anything
  that could mutate files.

## Search And Discovery

When qmd is available as an MCP server and the current project has an indexed
collection, prefer qmd `query` over grep/find for locating code. qmd is better
for semantic discovery:

- Finding implementations by describing what they do, not what they are named.
- Discovering related code across a large codebase.
- Answering "where is X handled?" questions.

Fall back to grep/find when:

- qmd is unavailable or the project has no indexed collection.
- You need exact string or regex matches, such as import paths, error messages,
  or symbol names.
- You need exhaustive occurrences for refactoring or renaming.

Never run `qmd collection add`, `qmd embed`, or `qmd update`; indexing is a
manual user action.

## Git Workflow

All tracked-file edits and commits MUST happen on isolated worktree branches.
Never edit or commit directly on `main`.

Codex hooks add guardrails for this workflow:

- `SessionStart` injects current git/worktree context.
- `PreToolUse` blocks `apply_patch` edits from the main worktree.
- `PreToolUse` checks Git shell commands for unsafe staging, commits, and
  pushes.

Hooks are guardrails, not the source of truth. Codex hook interception can miss
some tool paths, so follow these rules even if a hook does not fire.

Before editing tracked files, confirm the current branch/worktree state, create
an isolated worktree when needed, and run file edits from that worktree.

### Branch Creation

1. Create a worktree: `git worktree add ../<branch-name> -b <branch-name>`.
2. Change into the worktree directory to do all work there.
3. When done, return to the main worktree.

### Commit Discipline

- Commit each self-contained logical change atomically.
- Run commit commands from the worktree via the tool `workdir`; avoid
  `git -C ... commit`.
- Use conventional commits: `type(scope): description`.
- Allowed commit types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`,
  `ci`, `perf`.
- Stage files selectively by name.
- NEVER use `git add -A`, `git add .`, `git add --all`, or `git commit -a`.

### PR Workflow

- Push with an explicit refspec: `git push origin HEAD:<branch-name>`.
- Create PRs with `gh pr create`.
- Use merge commits only: `gh pr merge --merge`.
- NEVER squash or rebase.

### No-PR Workflow

This Codex setup defaults to `CODEX_GIT_WORKFLOW=no-pr`, matching the local
Claude mode. No-PR mode allows the final local merge after the review loop. It
does not relax selective staging, conventional commits, or the ban on rebase,
squash, and direct main-branch work.

When implementation is complete:

1. Commit all logical changes atomically in the worktree.
2. Run the review loop in `~/.codex/docs/no-pr-review.md` until clean.
3. Return to the main worktree.
4. Merge the feature branch into `main` with a merge commit. Run the merge from
   the main worktree via the tool `workdir`; avoid `git -C ... merge`.
5. Push main with `git push origin HEAD:main`.

After merge:

- Clean up with `git worktree remove ../<branch-name>`.
- Update main with `git checkout main && git pull`.

## Security Boundaries

NEVER read, write, or access these sensitive files or directories:

- `~/.ssh/*`
- `~/.gnupg/*`
- `~/.aws/credentials`
- `~/.kube/config`
- `~/.docker/config.json`
- `~/.netrc`
- `~/.config/gh/hosts.yml`
- Any `.env`, `.env.*`, or `.env.local` files.

NEVER run password manager commands:

- `bw get`, `bw list`, `bw unlock`
- `op read`, `op item get`

## Review And Verification

- Before accepting a code change, run the relevant tests, linters, format
  checks, type checks, or focused validation commands.
- Review the diff for bugs, regressions, risky patterns, missing tests, and
  workflow violations.
- Before the final response, summarize changed files, checks run, and anything
  that could not be verified.

## Review Agents

Use custom Codex agents when explicitly useful and available:

- `pr_explorer` for read-only codebase reconnaissance.
- `reviewer` for independent no-PR review passes.
- `docs_researcher` for current docs, API versions, and primary-source checks.

Do not delegate just to create parallelism. Delegate bounded work that can run
independently and report evidence.

## PR Context

When the user mentions a PR number, such as "PR #42" or "#42", fetch its
details with `gh pr view <number>` before responding.

## Codex Memory

Codex native memories are enabled for short-horizon personal preferences and
workflow facts. Treat them as convenience context, not durable documentation.
Durable project learnings belong in the wiki capture and ingest flow so future
agents can retrieve them through qmd.

When a session produces durable knowledge, prefer a small raw capture plus a
curated wiki page over storing large implementation detail in native memory.
Native memory generation is disabled for sessions that use external context,
which keeps qmd/web/MCP-derived facts out of personal memory unless curated.

## Wiki Capture

Codex writes structured session capture stubs to `${WIKI_VAULT}/raw/captures/`
from the `Stop` hook when a session has enough activity to be worth curating.
The hook parses Codex JSONL transcripts to capture first/last real user prompts,
the last assistant message, tool and command summaries, files touched by patches,
and the transcript path.

Claude has richer `PreCompact` and `SessionEnd` hook points. Codex currently
uses `Stop`, so capture timing is best-effort.

The capture is a raw inbox item, not a finished wiki page. Curate durable
learnings with the wiki ingest workflow or manually promote them from the
referenced transcript.

## Instruction Hygiene

- Keep this global file concise and focused on guidance that should apply in
  every repository.
- Put repository-specific rules in that repository's `AGENTS.md`.
- Put growing domain guidance in `docs/<domain>/AGENTS.md` and read it only
  when the task touches that domain.
- Promote repeated procedural workflows into Codex skills only after they recur.

## Domain Guidance

Read the matching domain guide before touching files in that area:

- Dockerfiles: `docs/docker/AGENTS.md`
- Kubernetes manifests: `docs/kubernetes/AGENTS.md`
- Terraform / OpenTofu: `docs/terraform-opentofu/AGENTS.md`
- GitHub Actions: `docs/github-actions/AGENTS.md`
- Helm charts: `docs/helm/AGENTS.md`
- Shell scripts: `docs/shell/AGENTS.md`
