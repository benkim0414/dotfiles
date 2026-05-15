# Codex User Instructions

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
- Keep the commit subject concise. Aim for 72 characters or fewer.
- Run relevant verification before committing when feasible. If no verification
  command is obvious, say that explicitly.
- Use Codex `/review` before finalizing non-trivial changes.
- If a commit message hook rejects a subject, read the rejection reason, inspect
  recent subjects with `git log --format=%s -50`, and retry with a valid
  conventional subject.
