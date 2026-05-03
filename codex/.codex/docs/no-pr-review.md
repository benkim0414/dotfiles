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

Use two independent Codex reviewer passes over the commit log and diff:

- Correctness and security: bugs, edge cases, validation, race conditions, hardcoded secrets, and security regressions.
- Design and quality: naming, duplication, unnecessary complexity, convention drift, missing tests, dead code, and maintainability.

If subagents are available, run both reviews in parallel and give each reviewer the full diff and commit log. If subagents are unavailable, run the two passes sequentially yourself with a fresh read of the diff each time.

Only act on findings with clear evidence and confidence of at least 80%.

## 3. Fix and repeat

Fix genuine issues atomically. Stage specific files by name, never with `git add -A`, `git add .`, `git add --all`, or `git commit -a`.

After any fix commit, return to step 1 and review the new full branch diff again.

## 4. Merge

When no genuine findings remain, merge back to main with a merge commit, then push with `git push origin HEAD:main`. Do not squash or rebase.
Run the merge command from the main worktree via the tool `workdir`; avoid `git -C ... merge`.
