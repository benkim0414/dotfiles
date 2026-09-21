# Atomic commits

- One commit, one logical change. Split when the subject needs "and",
  when staged files span unrelated areas, or when a fix and a refactor
  are mixed.
- Stage explicit paths: `git add <path>`. Never `-A`, `.`, `--all`,
  `--update`, `git commit -a`, `git commit -am`.

# Conventional commits

- Form: `type(scope): description`.
- Types: feat, fix, docs, chore, refactor, test, build, perf.
- Breaking change: append `!` to the type or scope.
