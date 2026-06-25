---
title: "Install local git hooks at the husky path, not .git/hooks, when core.hooksPath is set"
date: "2026-06-25"
category: "conventions"
module: "dotfiles/bin"
problem_type: "convention"
component: "tooling"
severity: "medium"
applies_when:
  - "writing a script that installs a git hook (post-merge, pre-commit, etc.) into a repo"
  - "the target repo uses husky, or anything else that sets core.hooksPath"
  - "a hook file you installed into .git/hooks exists but never fires"
  - "auditing why an automated git-hook-driven sync silently drifted"
tags:
  - git-hooks
  - husky
  - core-hookspath
  - post-merge
  - wiki-stage
  - convention
---

# Install local git hooks at the husky path, not .git/hooks, when core.hooksPath is set

## Context

`wiki-stage` mirrors a repo's tracked `docs/` tree into `~/workspace/wiki/raw/<repo>/`,
driven by a `post-merge` hook that `wiki-stage-install` wrote to
`.git/hooks/post-merge`. The mirror silently stopped: `raw/` drifted ~29 artifacts
behind `green-energy-group` and `ops`. The hook file existed and looked installed —
`cat .git/hooks/post-merge` showed the expected `exec wiki-stage` shim — yet it never
ran. Both repos use husky v9, which sets `core.hooksPath`.

## Guidance

When a repo sets `core.hooksPath`, **git ignores `.git/hooks/` entirely** and looks
only under that path. So a hook written to `.git/hooks/<name>` is dead in any husky
repo, with no error to signal it. Install the hook where git actually looks.

Detect husky by the **`.husky/` directory existing**, not by reading
`core.hooksPath` — test harnesses commonly set `core.hooksPath=/dev/null` to isolate
fixtures from global hooks (see Related), so keying off the config value misfires.

Write the user hook at `<repo_root>/.husky/post-merge`. This one location works for
both husky layouts:

- **husky v9** (`core.hooksPath=.husky/_`): git runs the generated `.husky/_/post-merge`
  wrapper, which sources `.husky/_/h`. That runner computes `s="${0%/*/*}/$h"` →
  `.husky/post-merge` and execs it. A top-level `.husky/post-merge` is sourced.
- **`core.hooksPath=.husky`** (older layout): git runs `.husky/post-merge` directly.

Keep a machine-local hook out of the **tracked** `.husky/` dir via `.git/info/exclude`,
and guard the body so it is a silent no-op for anyone without the tool on PATH:

```sh
#!/usr/bin/env sh
command -v wiki-stage >/dev/null 2>&1 || exit 0
exec wiki-stage
```

Finally, remove any dead `exec wiki-stage` shim still sitting in `.git/hooks/post-merge`
(only when it is your own shim — never a foreign hook), so the misleading
"looks installed but never runs" state is cleared.

## Why This Matters

A hook in `.git/hooks/` under an active `core.hooksPath` fails **silently and
invisibly** — the file is present, executable, and correct, but git never consults it.
Automation that depends on it (here, doc mirroring) drifts with no error, and the drift
is only noticed by an unrelated audit. Detecting husky by the `.husky/` dir rather than
the `core.hooksPath` value keeps the installer correct on machines and test fixtures
that legitimately point `core.hooksPath` elsewhere.

## When to Apply

- Any script that installs a git hook and must work in husky repos.
- Any "my git hook isn't firing" investigation — check `git config core.hooksPath`
  first; if set, `.git/hooks/` is dead.
- Reviewing or repairing a git-hook-driven sync that has drifted.

## Examples

Detection and install, before/after:

```bash
# BEFORE — always writes .git/hooks/, dead under husky:
hooks_dir="$common_dir/hooks"
hook="$hooks_dir/post-merge"

# AFTER — honour core.hooksPath via the .husky/ signal:
repo_root=$(dirname "$common_dir")
if [ -d "$repo_root/.husky" ]; then
  hook="$repo_root/.husky/post-merge"      # git (or husky's wrapper) finds it here
  husky=1
else
  hook="$common_dir/hooks/post-merge"      # plain repo: .git/hooks is live
  husky=0
fi
```

Keep it local and clear the dead shim (husky branch):

```bash
rel_hook=${hook#"$repo_root"/}                       # .husky/post-merge
grep -qxF "/$rel_hook" "$common_dir/info/exclude" 2>/dev/null \
  || printf '%s\n' "/$rel_hook" >> "$common_dir/info/exclude"
legacy="$common_dir/hooks/post-merge"
[ "$legacy" != "$hook" ] && [ -f "$legacy" ] \
  && grep -qx 'exec wiki-stage' "$legacy" 2>/dev/null && rm -f "$legacy"
```

## Related Issues

- `conventions/git-fixture-neutralize-global-hooks-2026-06-22.md` — the same
  `core.hooksPath` mechanism, opposite need: test fixtures *neutralize* a global
  `core.hooksPath` so fixture commits stay hermetic; hook installers must *honour* it
  so the hook lands where git looks.
