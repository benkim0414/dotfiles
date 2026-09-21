# Commit rules

One commit = one logical change. Split when the subject needs "and",
when staged files span unrelated areas, or when a fix and a refactor
are mixed.

Stage explicit paths: `git add <path>`. Never `-A`, `.`, `--all`,
`--update`, `git commit -a`, `git commit -am`.

Form: `type(scope): description`. Types: feat, fix, docs, chore,
refactor, test, ci, perf.
