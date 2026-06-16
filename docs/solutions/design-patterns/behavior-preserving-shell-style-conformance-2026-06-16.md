---
title: Behavior-preserving Google-shell-style conformance pass over a hook suite
date: 2026-06-16
category: design-patterns
module: dotfiles/claude
problem_type: design_pattern
component: tooling
severity: low
applies_when:
  - Restyling or reformatting working shell scripts to a style guide
  - Applying shfmt/shellcheck across a hook or script suite
  - Some scripts in the suite have no test coverage
tags:
  - behavior-preserving
  - shfmt
  - shellcheck
  - bash-hooks
  - google-shell-style
  - claude-hooks
  - regression-oracle
  - commit-scope
---

# Behavior-preserving Google-shell-style conformance pass over a hook suite

## Context

The 13 Claude Code hooks in `claude/.claude/hooks/` plus their 5 shared libs
in `claude/.claude/lib/` needed a readability + Google Shell Style Guide
conformance pass (comments, `shfmt` formatting, one `main()` wrapper) and a
new `hooks/README.md`. The hard constraint: change **zero** runtime behavior.
The risk concentrated in the ~9 hooks with no dedicated test suite — a reformat
that silently altered an exit code or emitted-JSON byte would go unnoticed.

This is the style-conformance sibling of the logic-dedup pass documented in
[behavior-preserving-bash-hook-dedup-2026-06-16](behavior-preserving-bash-hook-dedup-2026-06-16.md);
both share the same "mechanical change first, semantic change second, in
separate commits" discipline and the same hot-path-stays-lib-free constraint.
This doc's distinct contribution is the **baseline-output regression oracle**
for untested scripts and the set of justified style-guide deviations.

## Guidance

**1. Split mechanical from semantic, one commit each.**
Land a pure `shfmt -w` formatting commit first — it is tool-generated and
behavior-inert, so review is trivial and behavior risk is isolated to a pass a
tool verifies. Then layer hand-written comments / `main()` wrappers in separate
commits. Never mix a reformat with a hand edit in one diff.

```
chore(brewfile): add shfmt formatter
style(claude): shfmt-format hooks and libs          # mechanical, tool-verified
refactor(claude): wrap notify hook body in main()   # structural, behavior-preserving
docs(claude): normalize comments for <group> hooks  # semantic, hand-written
docs(claude): add function comment blocks to hook libs
docs(claude): add hooks README
```

**2. Build a baseline-output harness as a regression oracle for untested scripts.**
Before touching anything, drive each hook with a fixed JSON payload in a
throwaway `HOME`/`XDG` env and capture stdout + stderr + exit code. Re-run and
diff after every task. Identical output across the whole pass is the proof of
behavior preservation that the missing test suites cannot give you.

```bash
# /tmp harness (never committed). run() captures .out/.err/.rc per hook.
export HOME="$OUT/fakehome" XDG_RUNTIME_DIR="$OUT/xdg"   # side-effects hit nothing real
run() { printf '%s' "$2" | bash "$HOOKS/$1" >"$OUT/$1.out" 2>"$OUT/$1.err"; echo $? >"$OUT/$1.rc"; }
run git-session-start.sh '{"hook_event_name":"SessionStart","cwd":"'"$CWD"'","session_id":"base1"}'
# ... one run per hook ...
# After each task: diff before/ vs after/ on .out/.err/.rc — expect zero diff.
```

**3. Verification stack** (run after every task, all must pass):
`shfmt -i 2 -ci -bn -d` reports zero diff · `shellcheck --severity=warning`
clean · the existing test suites green · baseline diff clean.

**4. Record justified deviations instead of forcing the rule.**
- Keep `#!/usr/bin/env bash` (Google §2 wants `/bin/bash`): macOS ships bash
  3.2 at `/bin/bash`; Homebrew bash 5 lives outside `/bin`. `env bash` selects
  modern bash on both platforms.
- `read-once.sh` keeps **no** `main()` wrapper despite §7.7, because its
  per-tool fast-exits intentionally run *before* it sources its lib (a hot-path
  optimization). Hoisting its function above that boundary would defeat it.
  Document the deviation in the file header and the README.

**5. `shellcheck` clean bar = warning+ severity, not zero findings.**
SC1091 (can't follow a dynamically-computed `source "$(dirname …)"` path) and
an inherent SC2012 are `info`-level and unavoidable; chasing them to zero adds
noise or risks behavior. Treat `--severity=warning` clean as the gate and note
the accepted `info` findings in the README.

**6. Commit scope names the component, not the directory.**
Hooks and libs live in the `claude` package → scope `claude` (it appears in
`git log` history). `hooks` would trip the commit-scope **S3** path-segment
signal (matches the `hooks/` path, absent from history). The Brewfile change is
the lone exception → scope `brewfile`. See
[commit-scope-signal-driven-validation-2026-05-21](../conventions/commit-scope-signal-driven-validation-2026-05-21.md).

## Why This Matters

Reformatting tools are *mostly* behavior-inert, but "mostly" is not "provably."
On a suite where most scripts have no tests, the only trustworthy preservation
guarantee is an output diff against the original. The mechanical/semantic commit
split keeps that diff reviewable; the baseline harness makes it verifiable. The
documented deviations stop a future contributor (or a strict reading of the
style guide) from "fixing" `read-once.sh`'s structure and silently regressing
the hot path.

## When to Apply

- Any style-guide / `shfmt` / `shellcheck` conformance pass over working shell
  scripts, especially a hook or CLI suite.
- Whenever part of the suite lacks test coverage — build the baseline oracle
  before editing.
- Whenever a style rule fights a deliberate performance or portability choice —
  deviate and document, don't force.

## Examples

`shfmt -i 2 -ci -bn` normalizations are all behavior-inert — redirect spacing
(`>> "x"` → `>>"x"`), arithmetic spacing (`(( x ))` → `((x))`), case-pattern
spacing, line-continuation repositioning, one-line-compound expansion:

```bash
# before
if (( _t_skip )); then _t_skip=0; continue; fi
# after (shfmt)
if ((_t_skip)); then
  _t_skip=0
  continue
fi
```

The `main()` wrap stays behavior-identical only if body vars are NOT localized
(they must remain global) and early exits stay `exit`, not `return`:

```bash
send_osc777() { ...; }            # helper hoisted above main per §7.6
main() {
  INPUT=$(cat)                    # NOT `local` — stays global, as before
  [[ "$NTYPE" == ... ]] || exit 0 # `exit` still terminates the script
  ...
}
main "$@"
```

## Related

- [behavior-preserving-bash-hook-dedup-2026-06-16](behavior-preserving-bash-hook-dedup-2026-06-16.md)
  — same hook suite; that doc is the logic-dedup pass, this is the
  style-conformance pass. Shared discipline: mechanical-first commits,
  hot-path-stays-lib-free.
- [commit-scope-signal-driven-validation-2026-05-21](../conventions/commit-scope-signal-driven-validation-2026-05-21.md)
  — the authoritative source for why `claude` (not `hooks`) is the correct
  commit scope here (S3 path-segment signal).
- `claude/.claude/hooks/README.md` — the reference produced by this pass;
  records the two style-guide deviations.
