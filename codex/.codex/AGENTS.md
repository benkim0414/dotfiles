# Codex User Instructions

## Subagent Approval Contract

- Subagents inherit durable Codex config from `$CODEX_HOME/config.toml`.
- Keep `approval_policy = "on-request"`; do not bypass the sandbox globally.
- Routine sandbox-compatible repository work should flow through the configured auto reviewer.
- Sensitive operations require direct user approval and must not be approved by auto-review: destructive commands, network access, credential access, writes outside configured workspace roots, and history rewrites.
- Persistent prefix rules must be narrow and command-specific. Do not persist broad runtime prefixes such as `bash`, `python`, `node`, `ruby`, `perl`, or `sh`.

## Worktree Isolation

- For any change in a Git repository, work from a linked Git worktree rather than the repository's main worktree.
- Use the repository-local convention `git worktree add .worktrees/<slug> -b <branch>` and continue from `.worktrees/<slug>`.
- Generated workflow artifacts are part of the feature branch. This includes Superpowers specs in `docs/superpowers/specs/`, Superpowers plans in `docs/superpowers/plans/`, Compound solution docs in `docs/solutions/`, and normal code or config changes.
- A Codex PreToolUse hook enforces this for repo writes. If it blocks a write, create a linked worktree using the hook's suggested command, or enter the appropriate existing linked worktree.

## Git Commit Workflow

- Commit each self-contained logical change separately.
- Use conventional commit subjects: `type(scope): description`.
- Prefer these types unless the project documents a different convention:
  `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, and `perf`.
- Stage explicit paths only. Do not use `git add -A`, `git add --all`,
  `git add -u`, `git add .`, `git commit -a`, or `git commit -am`.
- Before committing, inspect `git diff` and `git diff --cached`.
- If the working tree contains unrelated edits, split them into separate
  commits by staging only the files for one logical change at a time.
- Choose commit scopes from recent project history when a clear scope exists.
  A new scope is acceptable when the project genuinely needs one.
- For generated or planning documentation, choose the scope from the component,
  product area, or domain described by the staged content. Do not infer scope
  from the document format, workflow name, generator name, or directory name
  unless that system is genuinely what the commit changes.
  Prefer `docs(<affected-component>): describe <change>` over
  `docs(<artifact-or-generator-name>): describe <change>`. If the change is
  repo-wide and no component dominates, omit the scope.
- Keep the commit subject concise. Aim for 72 characters or fewer.
- Run relevant verification before committing when feasible. If no verification
  command is obvious, say that explicitly.
- Use Codex `/review` before finalizing non-trivial changes.
- If a commit message hook rejects a subject, read the rejection reason, inspect
  recent subjects with `git log --format=%s -50`, and retry with a valid
  conventional subject.
