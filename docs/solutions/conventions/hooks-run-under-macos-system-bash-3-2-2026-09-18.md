---
title: "Hooks run under macOS system bash 3.2, not the shebang"
date: 2026-09-18
category: conventions
module: claude-code-hooks
problem_type: convention
component: tooling
severity: high
related_components:
  - shell_scripting
  - development_workflow
  - codex
applies_when:
  - "Writing or editing anything under claude/.claude/hooks or claude/.claude/lib"
  - "Writing or editing anything under codex/.codex/hooks"
  - "Adding a hook registration to settings.base.json or config.base.toml"
  - "Reaching for ${x,,}, declare -A, local -n, mapfile, or a control-character IFS"
  - "A hook appears to do nothing and produces no error"
tags:
  - bash
  - bash-3.2
  - macos
  - hooks
  - portability
  - silent-failure
  - shebang
  - dotfiles
---

# Hooks run under macOS system bash 3.2, not the shebang

## The invocation model

Hook registrations name the interpreter explicitly:

```json
"command": "bash $HOME/.claude/hooks/permission-policy.sh"
```

```toml
command = 'bash "$HOME/.codex/hooks/atomic-commits.sh"'
```

There are 16 such registrations — 14 in `claude/.claude/settings.base.json`, 2
in `codex/.codex/config.base.toml`. Because `bash` is named on the command
line, **the `#!/usr/bin/env bash` shebang is never consulted.** The interpreter
is whatever `bash` resolves to on `PATH`, and on macOS that is `/bin/bash`
**3.2.57** — released 2007, kept at that version for GPLv3 licensing reasons.
Homebrew's bash 5 exists at `/opt/homebrew/bin/bash` but does not win `PATH`
here.

So a hook, and every lib it sources, must be bash 3.2 syntax. Fixing the
shebang does not help. Nothing about the file says this.

## What it actually cost

Three hooks were entirely dead on this machine, for an unknown length of time,
and the only symptom was four test suites failing on `main` that nobody ran:

- **`lib/permission-policy.sh`** used `${url,,}` in `check_web_fetch`. On 3.2
  that raises `bad substitution`, `url_lc` stays empty, and every matcher falls
  through. Fetches to webhook and paste hosts, oversized query strings, and
  URLs referencing local filesystem paths were never flagged for confirmation.
  This is a security hook whose WebFetch half had never once fired.
- **`hooks/read-once.sh`** joined seven stdin fields on SOH and split them with
  `IFS=$'\x01' read`. bash 3.2 accepts that `IFS` assignment and then declines
  to split on a control character — the separator stays *inside* the value:

  ```
  $ /bin/bash -c 'IFS=$'"'"'\x01'"'"' read -r a b c < <(printf "one\x01two\x01three"); echo "[$a][$b][$c]"'
  [one<0x01>two<0x01>three][][]
  ```

  All seven fields landed in `SESSION_ID`, the UUID regex failed, and the hook
  exited 0 on every call. read-once had never denied a repeat read.
- **`lib/notify-pane.sh`** used `local -A`. bash 3.2 prints
  `local: -A: invalid option`, never applies `local` (so the variables leak to
  global scope), and degrades them to indexed arrays. It kept working only by
  accident: the subscripts are numeric pids, which sparse indexed arrays
  handle.

Plus `bin/.local/bin/tmux-attention-picker` (`declare -A`, the `Prefix+A`
popup, listed no sessions), and — still outstanding — ten `local -n` namerefs
in `codex/.codex/hooks/`, where `atomic-commits.sh` dies with
`local: -n: invalid option` and exits 2.

## Why every one of these is silent

This is the part worth keeping. Each mechanism fails quietly for its own
reason, and none of them surfaces to the user:

| Construct | On bash 3.2 | Why nothing is reported |
| --- | --- | --- |
| `${x,,}` | `bad substitution` to stderr, expansion yields `""` | The hook's stderr is not shown; an empty string makes the guarded `if` simply not match |
| `IFS=$'\x01' read` | assignment accepted, no split | No error at all. The data is intact but in the wrong variable |
| `local -A` / `declare -A` | `invalid option` to stderr | Degrades to an indexed array, which often still works |
| `local -n` | `invalid option`, function returns 2 | `set -e` kills the hook; a dead hook looks like a permissive one |

A PreToolUse hook that exits 0 without output means *allow*. So every one of
these failures reads as "this hook had no opinion" rather than "this hook is
broken". **A silently absent guard is indistinguishable from a guard that
passed.**

## Rules

**Write bash 3.2 for anything a hook can reach.** That includes every lib a
hook sources, transitively.

**Lowercase through `to_lower`** from `claude/.claude/lib/portability.sh` —
the file that already exists for exactly this class of gap. It costs a `tr`
subprocess, which is noise beside the `jq` forks these hooks already pay.

**No control-character `IFS`.** If fields need separating, note that tab is
IFS-whitespace and collapses empty fields — which is why SOH was chosen here in
the first place. read-once now avoids separators entirely: jq emits one
`@sh`-quoted assignment per field and the block is `eval`'d. If you take that
route, force every interpolation through `tostring` first; see
[jq @sh emits multiple words for non-scalars](jq-sh-array-breaks-eval-bridge-2026-09-18.md)
for why that is load-bearing rather than tidy.

**Numeric-keyed maps can be indexed arrays.** bash arrays are sparse, so real
pid values work as subscripts with no associative array needed. Guard the
subscript as numeric: an indexed subscript is evaluated arithmetically, so
garbage is an error rather than a missing key.

**A standalone script may require bash 4+ instead, by re-exec.** A hook cannot
— a sourced lib has nowhere to re-exec to — but a script like
`tmux-attention-picker` can. Check each candidate reports bash 4+ *before*
exec'ing it, and carry a sentinel so the retry happens once:
`/usr/local/bin/bash` is often a symlink to `/bin/bash`, and exec'ing it
unconditionally loops at roughly 550 execs a second, which inside a tmux popup
looks like a hang.

## Verification

`claude/.claude/tests/bash-portability/run.sh` rejects bash 4+ constructs and
control-character `IFS` separators in tracked shell files, exempting files whose
`BASH_VERSINFO` comparison is followed by a real `exec`. It does **not** yet
detect namerefs, because the codex sites are unfixed; the pattern to add is
recorded in the file.

To check a hook by hand, run it the way its config does — `bash <path>`, not
`./path` — or force the old interpreter explicitly:

```sh
printf '%s' '<payload json>' | /bin/bash claude/.claude/hooks/<hook>.sh
```

A green suite under `/opt/homebrew/bin/bash` proves nothing about production.

## Source

Found while fixing four test suites that had been failing on `main`. The suites
were the only thing that could have revealed this, and nothing ran them.

- Related: [Assertions that pass when they cannot check](assertions-that-pass-when-they-cannot-check-2026-09-18.md)
