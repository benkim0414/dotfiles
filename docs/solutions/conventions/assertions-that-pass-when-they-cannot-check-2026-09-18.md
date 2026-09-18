---
title: "Assertions that pass when they cannot check"
date: 2026-09-18
category: conventions
module: repo-test-harness
problem_type: convention
component: tooling
severity: high
related_components:
  - development_workflow
  - shell_scripting
applies_when:
  - "Writing a new <package>/tests/<name>/run.sh suite"
  - "Adding an assertion that shells out to grep, git, jq, or a file read"
  - "Reviewing a test that guards a silent-failure configuration"
  - "Excluding items from a checked set inside a test"
tags:
  - testing
  - false-pass
  - bash
  - shell
  - test-design
  - mutation-testing
  - repo-agnostic
  - dotfiles
---

# Assertions that pass when they cannot check

## Problem

This repo's test suites share a house convention: a `fail` counter with `ok`
and `bad` helpers, one assertion per condition, `exit $fail` at the end. Six
suites across four packages use it (`bin/tests/wiki-stage`,
`bin/tests/warp-install`, `zsh/tests/eval-cache`,
`zsh/tests/codex-command-helpers`, `claude/.claude/tests/output-style`,
`caveman/tests/caveman-default-off`).

The convention has a structural hazard: **`bad` only fires from an explicit
branch you wrote.** Any path that does not reach an assertion contributes
nothing to `fail`, so "I could not check" is indistinguishable from "I checked
and it was fine". The suite prints `all passed` and exits 0 either way.

Three separate instances of this appeared in a single session's new tests, all
three found by code review rather than by the tests themselves:

1. **A command whose failure mode is also its success mode.**
   `grep -rn PATTERN "$REPO/zsh"` returns non-zero when the pattern is absent
   *and* when the directory does not exist. The assertion was written as
   `if grep ...; then bad; else ok; fi`, so deleting `zsh/` made it pass. With
   a different shell package exporting the very variable under test, it still
   passed.

2. **A parser that accepts malformed input.** An awk frontmatter reader opened
   on a leading `---` and exited at the next one, but never required that a
   closing `---` was found. Deleting the closing delimiter left it scanning the
   whole document body, where it still found the keys it wanted. The consumer
   under test (Claude Code) would have parsed no frontmatter at all.

3. **A tool error read as a clean result.** `git ls-files` outside a git
   repository writes to stderr and produces no stdout. The result variable was
   empty, the emptiness was read as "nothing found", and the suite passed with
   the forbidden file sitting in the tree.

A fourth variant is not a false pass but the same family: **silent
exclusion.** An unanchored regex excluded 17 of 74 theme tokens from a contrast
check while printing nothing about the exclusions. A genuinely failing token
whose name merely contained `background` would have vanished from the report
with no trace, and the reader could not tell a checked token from a skipped
one.

## Why the final code does not show this

Each test now contains the fix, not the failure mode. Reading
`caveman/tests/caveman-default-off/run.sh` today shows a `git rev-parse`
precondition and a widened search, which look like ordinary care rather than
scar tissue. Nothing in the file says that its earlier form reported `ok` while
looking at a directory that did not exist. That is the reasoning worth keeping.

## Rules

**Gate on the precondition, separately from the assertion.** If a check needs
git, a directory, or a file, assert that it is there before asserting anything
about its contents, and fail the suite when it is not:

```bash
if ! (cd "$REPO" && git rev-parse --git-dir >/dev/null 2>&1); then
  bad "$REPO is not a git repository; the checks below cannot run"
  echo; echo "<suite>: FAILURES"; exit 1
fi
```

**Never let one branch mean two things.** `grep` returning non-zero is the
canonical trap. Prefer a form whose result distinguishes absent-from-broken, or
constrain the search to a surface you have already asserted exists.

**Validate structure before reading values out of it.** A parser that finds the
key it wants inside malformed input has told you nothing about whether the real
consumer will.

**Print every exclusion, with a reason.** A skipped item must be visible:

```bash
skip "${token} (background fill)"
```

A silent skip is indistinguishable from a pass, which is the same defect in a
different costume.

**Mutation-test every guard before trusting it.** Break the thing the assertion
protects, confirm the suite goes red, restore. An assertion that has never been
observed failing is not yet a test. All four defects above were found this way,
and none by the suites passing.

## Applies to

Any new `<package>/tests/<name>/run.sh`. The six existing suites listed above
have not been audited against these rules; the three defects were found only in
tests written on 2026-09-18.

Two suites, `claude/.claude/tests/permission-policy` and
`claude/.claude/tests/read-once`, fail on `main` as of 2026-09-18 and are
unrelated to this pattern — `permission-policy` uses `${url,,}`, a bash 4
expansion, while `bash` first on `PATH` is macOS `/bin/bash` 3.2.57. That is a
loud failure nobody was running rather than a silent pass, and it is worth
fixing separately.

## Source

Found during code review of the response-readability branch.

- Design: `docs/superpowers/specs/2026-09-18-claude-response-readability-design.md`
- Plan: `docs/superpowers/plans/2026-09-18-claude-response-readability.md`
