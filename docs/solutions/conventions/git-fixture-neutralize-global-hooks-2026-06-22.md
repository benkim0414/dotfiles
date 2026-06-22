---
title: "Neutralize global core.hooksPath in git test fixtures"
date: "2026-06-22"
category: "conventions"
module: "dotfiles/tests"
problem_type: "convention"
component: "testing_framework"
severity: "medium"
applies_when:
  - "writing a shell test harness that calls git init to create throwaway fixture repos"
  - "any test that runs git commit inside a fixture repo on a machine with a global core.hooksPath"
  - "adding a make_repo() or equivalent helper in a bash test suite"
  - "porting or running dotfiles tests on a machine where global git hooks may differ"
tags:
  - git-hooks
  - test-fixtures
  - core-hookspath
  - shell-testing
  - test-hermetic
  - convention
---

# Neutralize global core.hooksPath in git test fixtures

## Context

Bash test harnesses that create throwaway git repos as fixtures inherit the
process's global git configuration, including `core.hooksPath`. This dotfiles
repo sets a global `core.hooksPath` pointing at stowed hooks (the
conventional-commit message validator and `git-safety.sh`). So every
`git commit` run inside a fixture repo fires those hooks. A fixture setup
commit with a bare message like `init` fails the conventional-commit check —
printing noise into test output and, on a machine where the hook exits
nonzero, blocking the commit outright.

This surfaced during code review of `tests/wiki-stage/run.sh`, whose
`make_repo()` helper did `git init` then `git commit -q -m init`.

## Guidance

After `git init`, immediately neutralize the global hook path in the fixture:

```sh
git -C "$root" config core.hooksPath /dev/null   # isolate from global git hooks
```

`/dev/null` is a character device, not a directory. Git resolves hooks by
listing files in the `hooksPath` directory; when that path is not a directory
it finds nothing and skips all hooks. The fixture then runs hermetically
regardless of the caller's global git config.

Make this the line right after `git init` in every `make_repo`-style helper,
before any commit:

```sh
# before — fixture inherits the global core.hooksPath
make_repo() {
  local name=$1 root="$TMP/$1"
  mkdir -p "$root"
  git -C "$root" init -q
  git -C "$root" config user.email t@t.t
  git -C "$root" config user.name t
  git -C "$root" add docs/superpowers/specs/a.md
  git -C "$root" commit -q -m init   # fires the global commit-msg hook; "init" rejected
}

# after — hermetic fixture
make_repo() {
  local name=$1 root="$TMP/$1"
  mkdir -p "$root"
  git -C "$root" init -q
  git -C "$root" config user.email t@t.t
  git -C "$root" config user.name t
  git -C "$root" config core.hooksPath /dev/null   # isolate from global git hooks
  git -C "$root" add docs/superpowers/specs/a.md
  git -C "$root" commit -q -m init
}
```

The broader principle: a git fixture must explicitly override any ambient
global git config that changes behavior — `core.hooksPath` above all, but also
the likes of `commit.gpgSign`, `core.autocrlf`, and a global `.gitattributes`.
Do not assume the test environment is clean.

## Why This Matters

Two distinct failure modes:

1. **Output noise.** Even when the hook only warns (exit 0), it prints
   rejection text into test stdout. Lines like
   `COMMIT REJECTED: subject does not follow conventional commits` interleave
   with test results, hiding real failures and breaking grep-based assertions.

2. **Portability failure — green locally, red on CI.** If the global hook
   exits nonzero (a hard-blocking hook legitimately may), the fixture's setup
   commit fails, leaving the repo with no commits. `git ls-files` then returns
   nothing, and every downstream test that assumes a populated history fails
   with a symptom unrelated to what it is actually testing. The author's
   machine (hook warn-only or absent) stays green; CI or a colleague's machine
   (hook hard-blocks) goes red. This is exactly the environment-dependent
   failure class that makes a suite untrustworthy.

## When to Apply

- Writing shell or bats tests that `git init` throwaway fixture repos.
- The surrounding repo or the author's global config sets `core.hooksPath` to
  a non-empty hooks directory.
- A fixture commit uses a message that would not pass the ambient hook (bare
  words, non-conventional format), or you cannot guarantee the hook exits zero
  on every target machine.

Standing practice: add `git -C "$root" config core.hooksPath /dev/null` as the
line after `git init` in every fixture helper.

## Examples

Symptom visible in test output before the fix:

```
COMMIT REJECTED: subject does not follow conventional commits
```

Verification — count rejection lines before and after:

```sh
# before fix
bash tests/wiki-stage/run.sh 2>&1 | grep -c "COMMIT REJECTED"   # 6

# after fix
bash tests/wiki-stage/run.sh 2>&1 | grep -c "COMMIT REJECTED"   # 0
```

Full suite after the fix: 10/10 pass, zero hook noise.

## Related

- [Behavior-preserving bash hook dedup](../design-patterns/behavior-preserving-bash-hook-dedup-2026-06-16.md)
  — a complementary git-fixture hygiene pitfall (macOS `mktemp` fixtures need
  `pwd -P` so `/var` vs `/private/var` symlink resolution does not break git
  path comparisons). Same discipline (isolate the fixture from ambient git
  internals), different mechanism.
- [Commit-scope signal-driven validation](commit-scope-signal-driven-validation-2026-05-21.md)
  — documents the `git-safety.sh` / commit-scope hook that fires inside
  unguarded fixtures.
