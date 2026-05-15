# Codex Atomic Commit Workflow Design

## Context

This dotfiles repo already has a Claude Code workflow that enforces worktree
isolation, selective staging, and conventional commit messages through
Claude-specific hooks and commands. Recent repository history also follows
conventional commits, such as `feat(codex): ...`, `fix(desktop): ...`, and
`docs(codex): ...`.

Codex should get the same outcome, but not a direct copy of the Claude setup.
Claude-specific mechanisms such as `EnterWorktree`, `ExitWorktree`, `MODE:
no-pr`, and Claude hook payloads do not map cleanly to Codex. The Codex setup
should instead use Codex-native instruction discovery, rules, and lightweight
hooks where they fit.

Official Codex documentation points to `AGENTS.md` as the durable mechanism for
user-level and project-specific instructions. It also recommends telling Codex
what testing, review, and verification mean for a project, using `/review` for
local code review, and using hooks for controlled command behavior.

## Goal

Configure Codex so it generally commits changes atomically with conventional
commit messages across any project, while keeping the workflow portable and low
maintenance.

## Non-Goals

- Do not port the full Claude Code workflow.
- Do not require every project to use the dotfiles repo's branch names, PR flow,
  or no-PR flow.
- Do not block valid project-specific workflows that intentionally use new
  conventional commit scopes.
- Do not add heavyweight automation that surprises Codex users in unrelated
  repositories.

## Recommended Approach

Use user-level advisory guidance plus light enforcement.

The durable behavior should live in the stowed Codex package under
`codex/.codex/`, so it becomes part of the user's Codex home after the normal
dotfiles sync/stow flow. Project repositories can still override or refine the
guidance with their own `AGENTS.md` files.

## Components

### User-Level Codex Instructions

Add `codex/.codex/AGENTS.md` with user-level working agreements:

- Commit each self-contained logical change separately.
- Use conventional commit subjects: `type(scope): description`.
- Prefer common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`,
  and `perf`.
- Stage explicit paths only.
- Do not use `git add -A`, `git add .`, `git add --all`, `git add -u`, or
  `git commit -a`.
- Inspect `git diff` and `git diff --cached` before committing.
- Split unrelated edits into separate commits.
- Choose scopes from recent project history when available, but allow a new
  scope when the project genuinely needs one.
- Run relevant verification before committing when feasible.
- Use Codex `/review` before finalizing non-trivial changes.

### Light Enforcement

Add a user-level Codex `PreToolUse` hook for shell commands that catches the
highest-risk habits without overfitting to one repository:

- Block blanket staging commands such as `git add -A`, `git add --all`,
  `git add -u`, and `git add .`.
- Block commit-all patterns such as `git commit -a` and `git commit -am`.
- Prefer guidance-style failures that tell Codex to stage explicit files for one
  logical change and then commit with a conventional subject.

This layer should not enforce repo-specific main-branch rules or PR rules. Those
belong in project instructions or project hooks, because they vary across
repositories. Codex rules can still be added later for approval policy, but they
are not the right primary mechanism here because these git commands usually run
inside the workspace sandbox.

### Existing Git Hook Compatibility

Keep the existing user-level Git `commit-msg` hook as the final conventional commit
validator. It already enforces allowed conventional commit types, subject
length, and known scopes based on recent history. Codex guidance should teach
Codex to work with that hook instead of duplicating all validation inside Codex.

## Data Flow

1. Codex starts in any repository and loads user-level instructions from
   `~/.codex/AGENTS.md`.
2. Codex then loads any project-level `AGENTS.md` guidance for the current repo.
3. During work, Codex follows the atomic commit workflow unless the
   project provides stricter local rules.
4. If Codex attempts broad staging or commit-all commands, the Codex hook layer
   blocks the command with a corrective message.
5. When Codex creates a commit, the existing Git `commit-msg` hook validates the
   final subject.

## Error Handling

- If broad staging is blocked, Codex should run `git status --short`, identify
  the files belonging to one logical change, stage those explicit paths, and
  retry.
- If the commit message hook rejects a subject, Codex should read the rejection
  reason, inspect recent commit scopes with `git log --format=%s -50`, then
  retry with a valid subject.
- If no obvious verification command exists, Codex should state that explicitly
  before committing or in its final summary.

## Testing

Verification should cover both static configuration and behavior:

- Confirm `codex/.codex/AGENTS.md` exists and contains the user-level workflow.
- Confirm the generated or stowed Codex home will expose that file as
  `~/.codex/AGENTS.md`.
- Test the hook directly with allowed and blocked git command payloads.
- Exercise the existing `commit-msg` hook with valid and invalid conventional
  commit message samples.

## Implementation Notes

- Prefer a small Codex-native implementation over copying Claude hook scripts.
- Keep enforcement generic enough to work across projects.
- Document the setup in the dotfiles README or `CLAUDE.md` package conventions
  only if the existing sync/stow flow needs clarification.
