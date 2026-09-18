---
title: "Codex worktree-guard does not guard shell commands"
date: 2026-09-18
category: tooling-decisions
module: codex-hooks
problem_type: bug
component: tooling
severity: critical
related_components:
  - security
  - development_workflow
  - shell_scripting
applies_when:
  - "Relying on codex/.codex/hooks/worktree-guard.sh to protect the main worktree"
  - "Editing worktree-guard.sh or reasoning about which of its functions run"
  - "Deciding whether to reconnect or delete its unreachable policy code"
tags:
  - codex
  - worktree-guard
  - hooks
  - security
  - dead-code
  - unguarded
  - dotfiles
status: open
---

# Codex worktree-guard does not guard shell commands

**Status: open.** This documents a finding, not a fix. The three fixes that
shipped alongside it are listed at the end.

## Finding

`codex/.codex/hooks/worktree-guard.sh` guards direct file-write tools and
allows **every** shell command unconditionally. The final dispatch, at the foot
of a 2,276-line file, is:

```bash
if is_direct_write_tool || is_mcp_write_tool; then
  ...                       # ~45 lines of real classification
  require_approval "$(approval_reason "primary worktree" "$repo_root")"
fi

if is_shell_tool || is_mcp_executor_tool; then
  exit 0
fi

exit 0
```

The shell branch is a stub. Both arms reach `exit 0`, so the `if` changes
nothing.

Measured against a fixture with a main worktree and a registered linked
worktree, all from inside the protected main worktree:

| Call | Tool | Decision |
| --- | --- | --- |
| `touch generated.txt` | Bash | **allow** |
| `rm -rf README.md` | Bash | **allow** |
| `git commit --allow-empty -m x` | Bash | **allow** |
| `git push --force origin main` | Bash | **allow** |
| `git checkout -B main` | Bash | **allow** |
| `touch <primary>/x.txt` from outside | Bash | **allow** |
| `rm -rf <primary>` from outside | Bash | **allow** |
| `Write <primary>/generated.txt` | Write | deny |
| `apply_patch` adding `repo.txt` | apply_patch | deny |

So the guard stops an agent writing a file with `Write`, and permits the same
agent doing it with `touch` — or force-pushing the main branch.

## Scale of the unreachable code

20 of the hook's 75 functions are defined and never referenced anywhere else in
the file, roughly 700 lines, about 31% of it. Verified two ways: a
reference count per function, then spot-checks by direct grep
(`block_reason` → 1 occurrence, its own definition; `canonical_path` → 35).

The orphaned set is not a collection of leftover helpers. It is, almost
exactly, the machinery the shell branch would need:

| Dead function | Line | Lines | What the shell branch would use it for |
| --- | --- | --- | --- |
| `command_text` | 603 | 26 | extract the command string from tool input |
| `mcp_executor_command_records` | 629 | 56 | extract commands from MCP executor payloads |
| `mcp_executor_command_record_cwd` | 685 | 11 | per-record working directory |
| `effective_cwd` | 145 | 31 | resolve the directory a command runs in |
| `git_command_cwd` | 1268 | 62 | working directory of a `git -C` invocation |
| `git_command_has_mismatched_git_dir` | 1330 | 96 | detect `--git-dir` pointing elsewhere |
| `has_unresolved_git_c_option` | 848 | 19 | `git -C` with a value it cannot resolve |
| `is_destructive_git_command` | 1426 | 8 | classify destructive git verbs |
| `command_targets_outside_git_repo` | 1128 | 83 | decide whether a command's targets escape the repo |
| `require_approval_for_shell_patch_targets` | 1018 | 47 | gate heredoc/patch writes issued through a shell |
| `main_worktree_root_for_path` | 867 | 16 | classify a path's main worktree |
| `main_worktree_root_for_target` | 910 | 16 | same, for a command target |
| `approval_required_worktree_root_for_target` | 975 | 9 | whether that target needs approval |
| `primary_worktree_root_for_current_repo` | 230 | 18 | resolve the protected root |
| `approval_category_for_base` | 2269 | 65 | categorise the decision |
| `block_reason` | 2225 | 16 | build the deny message |
| `is_allowed_primary_checkout_pull_command` | 1872 | 76 | allow-list: checkout/pull in primary |
| `is_allowed_worktree_lifecycle_git_command` | 1992 | 54 | allow-list: `git worktree add/remove` |
| `is_allowed_registered_worktree_touch_command` | 2046 | 29 | allow-list: `touch` into a registered worktree |
| `is_outside_repo_shell_command_allowed` | 2140 | 12 | allow-list: commands wholly outside any repo |

Five of those twenty are *allow*-lists. Their presence is the strongest signal
that the shell branch was designed to deny by default and carve out
exceptions — which is the opposite of what it does now.

## What the tests say the policy should be

The test suite encodes the intended behaviour, and it is far stricter than the
hook. Examples from `codex/.codex/tests/test-worktree-guard-hook.sh`:

```
line 464  approval required: mcp ctx_execute `touch generated.txt` in primary
line 500  approval required: `touch .worktrees/plain-dir/generated.txt`
                             -- "unregistered worktree-like path"
line 583  allowed:           `touch /tmp/worktree-guard-scratch-$$`
line 649  approval required: `git pull --ff-only; touch generated.txt`
line 653  allowed:           `touch .worktrees/nested-linked/generated-from-primary.txt`
line 693  approval required: `rg --pre touch fixture README.md`
line 701  approval required: `touch "<primary>/quoted-generated.txt"` from outside
line 729  approval required: `touch generated.txt` in primary
```

Those are precise, thoughtful expectations — including `rg --pre`, which smuggles
a command through a flag. None of them can pass while the branch is `exit 0`.

The suite aborts at line 464 (the first shell-ish expectation), so the ~200
assertions after it never ran. That is why this was invisible: the suite was
red on `main`, and its only failure signal was `set -e` stopping the script
with no message.

## Why nobody saw it

Three independent things had to line up, and they did:

1. **The hook fails open.** A PreToolUse hook that exits 0 without output means
   *allow*. A stub branch is indistinguishable from a branch that considered the
   command and approved it.
2. **The tests could not report.** Assertions signalled failure only by letting
   a bare `jq -e` trip `set -e`. An abort printed nothing — not the scenario,
   not the filter, not a count. Instrumenting them was a prerequisite for
   finding this, and dropping `set -e` to survey the damage is actively
   misleading, because the callers `echo "ok ..."` unconditionally and every
   assertion then reports success.
3. **Nothing ran the suite.** There is no CI, no aggregate runner, and the only
   git hook is a commit-message linter.

## The decision this leaves open

Reconnecting 700 lines of unreachable policy is not a mechanical fix, because
it is not knowable from the code which of these three is true:

- **The logic is finished and the call site was lost.** Then the fix is to wire
  the shell branch to it and let the suite's ~200 remaining assertions say
  whether it works.
- **The logic is unfinished.** Then the allow-lists exist but the deny path
  does not, and wiring it up would block ordinary work.
- **The logic was deliberately retired** in favour of the write-tool branch, and
  the tests are stale.

The first is most likely, on two pieces of evidence: the functions are coherent
and specific (`git_command_has_mismatched_git_dir` is 96 lines of real work,
not a stub), and the test file encodes matching expectations in detail. But
"most likely" is not a basis for changing what a security hook permits.

**Recommended next step:** wire the shell branch to the existing functions
behind an env switch (default off), then run the instrumented suite. The
assertions after line 464 become the specification — they will say immediately
whether the dead code implements the intended policy. Only flip the default
once they pass.

Until then, treat the codex worktree guard as protecting `Write`-style tools
only. It does not restrain shell commands, including destructive git.

## Shipped alongside this finding

Three fixes landed with it, all verified:

- **Nameref re-exec shim.** Both codex hooks use `local -n` (bash 4.3+) but are
  registered as `bash "$HOME/.codex/hooks/<x>.sh"`, so the shebang is bypassed
  and they ran under `/bin/bash` 3.2.57, where `local -n` fails and `set -e`
  kills the hook. `atomic-commits` was therefore not running at all. See
  [Hooks run under macOS system bash 3.2](../conventions/hooks-run-under-macos-system-bash-3-2-2026-09-18.md).
- **`canonical_path` bypass.** It resolved one directory level and otherwise
  returned the path unresolved; since `/var` is a symlink on macOS, an
  unresolved path could never prefix-match a worktree root already resolved by
  `pwd -P`, so `Write` to `<primary>/newdir/file` from outside went unguarded.
- **Test instrumentation.** An `ERR` trap with `errtrace` now names the failing
  command, exit status and call stack. Without it this finding was not
  reachable.

## Source

- Related: [Assertions that pass when they cannot check](../conventions/assertions-that-pass-when-they-cannot-check-2026-09-18.md)
- Related: [Hooks run under macOS system bash 3.2](../conventions/hooks-run-under-macos-system-bash-3-2-2026-09-18.md)
