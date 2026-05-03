# Global Codex Preferences

## Communication

- Never use emojis in responses.
- If requirements are ambiguous, underspecified, or open to multiple
  interpretations, ask clarifying questions before proceeding. This applies
  to task scope, implementation approach, edge cases, naming, and any
  decision that could go more than one way.
- Explain the reasoning behind config choices, not just what to set.
- Present the dry-run/plan/diff form of a command before the apply form;
  let the user review first.
- Use web search to look up current docs, API versions, or package versions
  -- training data goes stale; never guess at versions.

## Editor

- Default editor is nvim. Do not open VS Code or other GUI editors.

## Semantic Search (qmd)

When qmd is available as an MCP server and the current project has an indexed
collection, prefer qmd `query` over grep/find for locating code.
qmd returns semantically ranked results, which is more effective for:
- Finding implementations by describing what they do (not what they're named)
- Discovering related code across a large codebase
- Answering "where is X handled?" questions

Fall back to grep/find when:
- qmd is not available or the project has no indexed collection
- You need exact string/regex matches (import paths, error messages, symbol names)
- You need to find all occurrences exhaustively (refactoring, renaming)

Never run `qmd collection add`, `qmd embed`, or `qmd update` -- indexing
is a manual user action.

## Git Workflow

All work MUST happen on isolated worktree branches. Never commit or edit
directly on the main branch.

Codex hooks add guardrails for this workflow:
- `SessionStart` injects current git/worktree context.
- `PreToolUse` blocks `apply_patch` edits from the main worktree.
- `PreToolUse` checks Git shell commands for unsafe staging, commits, and pushes.

These hooks are guardrails, not the only source of truth. Codex hook
interception can miss some tool paths, so follow these instructions even if a
hook does not fire.

### Branch creation

1. Create a worktree: `git worktree add ../<branch-name> -b <branch-name>`
2. Change into the worktree directory to do all work there.
3. When done, return to the main worktree.

### Commit discipline

- Commit each self-contained logical change atomically.
- Run commit commands from the worktree via the tool `workdir`; avoid `git -C ... commit`.
- Use conventional commits: `type(scope): description`
  - Types: feat, fix, docs, chore, refactor, test, ci, perf
- Stage files selectively by name. NEVER use `git add -A`, `git add .`,
  `git add --all`, or `git commit -a`.

### Push and PR

- Push with explicit refspec: `git push origin HEAD:<branch-name>`
- Create PRs with `gh pr create`.
- Use merge commits only: `gh pr merge --merge`. NEVER squash or rebase.

### No-PR mode

This Codex setup defaults to `CODEX_GIT_WORKFLOW=no-pr`, matching the local
Claude mode.

When implementation is complete:

1. Commit all logical changes atomically in the worktree.
2. Run the review loop in `~/.codex/docs/no-pr-review.md` until clean.
3. Return to the main worktree.
4. Merge the feature branch into main with a merge commit.
   Run the merge from the main worktree via the tool `workdir`; avoid `git -C ... merge`.
5. Push main with `git push origin HEAD:main`.

No-PR mode allows the final local merge after the review loop. It does not
relax selective staging, conventional commits, or the ban on rebase/squash.

### After merge

- Clean up: `git worktree remove ../<branch-name>`
- Update main: `git checkout main && git pull`

## Security Boundaries

NEVER read, write, or access these sensitive files or directories:
- `~/.ssh/*` (private keys, config)
- `~/.gnupg/*` (GPG keys)
- `~/.aws/credentials`
- `~/.kube/config`
- `~/.docker/config.json`
- `~/.netrc`
- `~/.config/gh/hosts.yml`
- Any `.env`, `.env.*`, or `.env.local` files

NEVER run password manager commands:
- `bw get`, `bw list`, `bw unlock`
- `op read`, `op item get`

## Codex Memory

Codex native memories are enabled for short-horizon personal preferences and
workflow facts. Treat them as convenience context, not durable documentation.
Durable project learnings belong in the wiki capture and ingest flow so future
agents can retrieve them through qmd.

When a session produces durable knowledge, prefer a small raw capture plus a
curated wiki page over storing large implementation detail in native memory.
Native memory generation is disabled for sessions that use external context,
which keeps qmd/web/MCP-derived facts out of personal memory unless curated.

## Review Agents

Use custom Codex agents when explicitly useful and available:
- `pr_explorer` for read-only codebase reconnaissance.
- `reviewer` for independent no-PR review passes.
- `docs_researcher` for current docs, API versions, and primary-source checks.

Do not delegate just to create parallelism; delegate bounded work that can run
independently and report evidence.

## Session Start

- At the beginning of every session, run `git status` and `git branch` to
  establish context. Report the current branch and working tree state.
- If on main with uncommitted work, warn immediately.

## PR Context

- When the user mentions a PR number (e.g., "PR #42", "#42"), fetch its
  details with `gh pr view <number>` before responding.

## Wiki Capture

Codex writes structured session capture stubs to `${WIKI_VAULT}/raw/captures/`
from the `Stop` hook when a session has enough activity to be worth curating.
The hook parses Codex JSONL transcripts to capture first/last real user prompts,
the last assistant message, tool and command summaries, files touched by patches,
and the transcript path. Claude has richer `PreCompact` and `SessionEnd` hook
points; Codex currently uses `Stop`, so capture timing is best-effort.

The capture is a raw source, not a finished wiki page. Curate durable learnings
with the wiki ingest workflow or manually promote them from the referenced
transcript.

## Domain: Dockerfiles

- Pin base image tags to exact versions: `python:3.13.1-slim` not `python:3` or `python:latest`
- Always verify base image digests via web search -- never rely on training data
- Use multi-stage builds for compiled languages -- separate build deps from runtime
- Copy dependency manifests first (package.json, requirements.txt), then source -- maximizes layer cache hits
- Create and switch to non-root user: `RUN useradd -r appuser && USER appuser`
- Combine apt-get update and install in one RUN with cleanup: `RUN apt-get update && apt-get install -y pkg && rm -rf /var/lib/apt/lists/*`

## Domain: Kubernetes Manifests

Every Deployment/StatefulSet/DaemonSet must include:

### Security Context (Restricted profile)

- Pod-level: `runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault`
- Container-level: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`
- Never use hostNetwork, hostPID, hostIPC, or hostPath volumes
- Set `automountServiceAccountToken: false` unless the pod needs Kubernetes API access

### Resource Management

- Set both `resources.requests` and `resources.limits` (cpu, memory) on every container
- Add `livenessProbe` and `readinessProbe` on every container
- Include a `PodDisruptionBudget` for production workloads

### Image and Versioning

- Pin image tags to exact versions -- never use `:latest` or bare major/minor tags
- Always verify image digests via web search -- never rely on training data
- Use current stable apiVersions: `apps/v1`, `networking.k8s.io/v1`, `policy/v1`
- Label consistently: `app.kubernetes.io/name`, `app.kubernetes.io/version`, `app.kubernetes.io/component`

## Domain: Terraform / OpenTofu

- Always show `terraform plan` output before any apply -- never combine or skip the plan step
- Pin provider versions in required_providers: `version = "~> 5.0"` not `>= 5.0` or omitted
- Use remote backend with state locking (S3 + DynamoDB, or equivalent) -- never local state in shared environments
- Add `lifecycle { prevent_destroy = true }` on stateful resources (databases, storage, networking)
- Mark sensitive outputs with `sensitive = true` to prevent leaks in logs and CI output

## Domain: GitHub Actions

- Pin actions by full commit SHA, not tag: `actions/checkout@<sha>` not `@v4`
- Always declare a `permissions:` block at job level with least privilege -- omitting defaults to broad access
- Use OIDC (`id-token: write`) for cloud auth instead of long-lived credential secrets
- Guard comment-triggered workflows against self-triggers: `if: github.actor != 'claude[bot]'`

## Domain: Helm Charts

- Validate before committing: `helm lint --strict` and `helm template . --validate`
- Always verify chart versions via web search -- never rely on training data
- Provide complete defaults in values.yaml for all templated values
- Quote string interpolations in templates: `"{{ .Values.image.tag }}"` not bare `{{ .Values.image.tag }}`

## Domain: Shell Scripts

- ShellCheck must pass with no warnings before committing
