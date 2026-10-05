# Atomic commits

- One commit, one logical change. Split when the subject needs "and",
  when staged files span unrelated areas, or when a fix and a refactor
  are mixed.
- Stage explicit paths: `git add <path>`. Never `-A`, `.`, `--all`,
  `--update`, `git commit -a`, `git commit -am`.
- Before committing, run `git diff --cached --name-only` and confirm the
  staged set is exactly the change. A bare `git commit` sweeps in anything
  already in the index. Staged files under several top-level directories
  are a signal to split.

# Conventional commits

- Form: `type(scope): description`.
- Types: feat, fix, docs, chore, refactor, test, build, perf.
- Breaking change: append `!` to the type or scope.

## Scope

Scope names WHAT the commit changes (a component), not WHERE the file
lives. Read the diff before choosing it. Real scopes are the component
names already in the repo's `git log`. Omit the scope when no single
component dominates.

Reject a scope when it is:

- **S1 - a universal container**: `docs`, `doc`, `src`, `lib`, `bin`,
  `scripts`, `script`, `tests`, `test`, `assets`, `static`, `public`,
  `vendor`, `build`, `dist`, `target`, `packages`, `apps` -- unless the
  repo's `git log` already uses it as a scope.
- **S2 - the repo basename**: e.g. `myapp` in repo `myapp/`. No exception.
- **S3 - a path segment of the staged files**: the scope (or its `+s`
  plural) equals a directory segment of a staged path, e.g. `spec` when
  staging under `docs/superpowers/specs/`, `openspec` when staging under
  `openspec/changes/` -- unless the repo's `git log` already uses it.
- **S4 - new**: allowed by S1-S3 but absent from `git log`. Not wrong, but
  confirm it names a component, not an artifact directory.

```text
# Good
feat(<component>): <description>
docs(<component>): update <component> docs
docs: <repo-wide policy change>

# Bad
feat(spec): <description>         # artifact type (S3)
docs(<repo-name>): <description>  # repo name (S2)
docs(docs): <description>         # universal container (S1)
feat(<component>): change X and Y # "and" = two changes, split
```
