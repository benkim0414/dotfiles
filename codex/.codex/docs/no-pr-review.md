# Codex no-PR review loop

Run this loop on the feature branch before returning to main and merging.

## 1. Gather the branch diff

```sh
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
MAIN_BRANCH=${MAIN_BRANCH:-main}
MERGE_BASE=$(git merge-base HEAD "origin/${MAIN_BRANCH}")
git log --oneline "$MERGE_BASE..HEAD"
git diff "$MERGE_BASE..HEAD"
```

## 2. Run fresh reviews

Use two independent reviewer passes over the commit log and diff:

- Correctness and security: bugs, edge cases, validation, race conditions, hardcoded secrets, and security regressions.
- Design and quality: naming, duplication, unnecessary complexity, convention drift, missing tests, dead code, and maintainability.

When active instructions allow custom agents, use `reviewer` for both passes
with different focus prompts. Use `pr_explorer` first only when the diff needs
more codebase context, and use `docs_researcher` only for version-sensitive or
external API claims. If agents are unavailable or delegation is not allowed, run
the passes sequentially yourself with a fresh read of the diff each time.

Give each reviewer enough context to review the work product, not the session
history:

- Implementation summary and requirements or plan.
- `MERGE_BASE`, `HEAD`, commit log, diff stat, and full diff.
- Verification commands already run and their outcomes.
- Known limitations, skipped checks, or intentional deviations.

Calibrate findings by actual severity:

- Critical: bugs, security issues, data loss risks, or broken functionality.
- Important: missing requirements, fragile design, weak error handling, or real
  test gaps.
- Minor: style, documentation polish, or low-risk maintainability suggestions.

Each finding needs a file or command reference, why it matters, and a clear
verdict: ready to merge, ready with fixes, or not ready.

Only act on findings with clear evidence and confidence of at least 80%.

## 3. Fix and repeat

Fix genuine issues atomically. Stage specific files by name; do not use blanket staging or commit-all flags.

Before implementing reviewer feedback, verify it against the codebase. Push
back on findings that are technically wrong, context-blind, or out of scope.
Clarify unclear feedback before changing files. Fix one logical issue at a time
and run focused verification for that fix.

After any fix commit, return to step 1 and review the new full branch diff again.

## 4. Merge

When no genuine findings remain, finish the branch with the local no-PR flow:

1. Verify the relevant checks on the feature branch before merging.
2. Return to the main worktree.
3. Merge with a merge commit.
4. Verify the merged result when practical.
5. Push with an explicit `HEAD:main` refspec.
6. Remove the worktree only after merge and push succeed.

Do not squash or rebase. Do not discard or delete work without explicit user
confirmation.
Run the merge command from the main worktree via the tool `workdir`; avoid `git -C ... merge`.
