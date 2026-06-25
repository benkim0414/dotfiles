# wiki-stage husky-aware post-merge hook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `wiki-stage-install` install the `post-merge` hook where git actually looks in husky repos (`.husky/post-merge`), kept local-only, so `wiki-stage` mirrors `docs/` into the wiki again.

**Architecture:** `wiki-stage-install` currently writes `.git/hooks/post-merge`. When a repo has a `.husky/` dir, git's `core.hooksPath` redirects hook lookup away from `.git/hooks/`, so the shim is dead. Detect `.husky/` and install the guarded hook at `.husky/post-merge` (husky's `_/post-merge` wrapper sources it on v9; git runs it directly when `hooksPath=.husky`). Keep it out of git via `.git/info/exclude` and remove the dead shim.

**Tech Stack:** POSIX sh / bash, git hooks, husky v9, the existing `tests/wiki-stage/run.sh` harness.

## Global Constraints

- Detection signal is **`$repo_root/.husky` directory exists**, NOT "`core.hooksPath` is set" — the test harness sets `core.hooksPath=/dev/null` for isolation, so keying off `core.hooksPath` would break the existing `.git/hooks/` tests.
- The non-husky branch must keep writing the **exact** 2-line shim `#!/usr/bin/env sh\nexec wiki-stage\n` — `tests/wiki-stage/run.sh` t7a byte-compares it.
- Husky hook body must include the guard line `command -v wiki-stage >/dev/null 2>&1 || exit 0` verbatim.
- "Ours" is identified by a line matching `exec wiki-stage` (true of both the old shim and the new guarded hook).
- Local-only: never commit the hook into the tracked `.husky/` dir. Exclude entry is `/.husky/post-merge` in `<git-common-dir>/info/exclude`.
- Commit style for dotfiles: conventional commits (`type(scope): desc`), scope `wiki-stage`.
- dotfiles is **no-pr** mode: finish with a local merge, not a PR.

---

## File Structure

- `bin/.local/bin/wiki-stage-install` — gains husky-awareness, exclude write, dead-shim cleanup. Single responsibility (install/repair the hook) unchanged.
- `tests/wiki-stage/run.sh` — gains `t8_husky_hookspath` and its registration in `main()`.
- `wiki-stage` itself is **unchanged** (its mirror logic already works; the bug is purely install-location).

---

### Task 1: Husky-aware install + regression test

**Files:**
- Modify: `bin/.local/bin/wiki-stage-install` (full rewrite, below)
- Modify: `tests/wiki-stage/run.sh` (add `t8_husky_hookspath`, register in `main`)

**Interfaces:**
- Consumes: `wiki-stage` on PATH (the hook execs it); `git rev-parse --git-common-dir`.
- Produces: a `post-merge` hook at `.husky/post-merge` (husky repos) or `.git/hooks/post-merge` (plain repos); an idempotent `/.husky/post-merge` line in `info/exclude`; removal of a dead `.git/hooks/post-merge` wiki-stage shim in husky repos.

- [ ] **Step 1: Add the failing husky test case**

Insert this function after `t7_install` (before `main`) in `tests/wiki-stage/run.sh`:

```bash
t8_husky_hookspath() {
  # Husky repos: git ignores .git/hooks/ (core.hooksPath), so the hook must
  # land at .husky/post-merge. Detector keys off the .husky/ dir, not hooksPath
  # (make_repo already sets core.hooksPath=/dev/null for isolation).
  local root; root=$(make_repo husk)
  mkdir -p "$root/.husky/_"
  git -C "$root" config core.hooksPath .husky/_     # husky v9 layout, for realism
  # The bug we repair: a dead wiki-stage shim sitting in .git/hooks/.
  mkdir -p "$root/.git/hooks"
  printf '%s\n' '#!/usr/bin/env sh' 'exec wiki-stage' > "$root/.git/hooks/post-merge"
  chmod +x "$root/.git/hooks/post-merge"

  ( cd "$root" && "$INSTALL" >/dev/null )

  local hook="$root/.husky/post-merge"
  if [ -x "$hook" ] \
     && grep -qFx 'command -v wiki-stage >/dev/null 2>&1 || exit 0' "$hook" \
     && grep -qx 'exec wiki-stage' "$hook"; then
    ok "t8a husky hook installed with guard"; else bad "t8a husky hook installed with guard"; fi

  if grep -qFx '/.husky/post-merge' "$root/.git/info/exclude" 2>/dev/null; then
    ok "t8b husky hook kept local via exclude"; else bad "t8b husky hook exclude"; fi

  if [ ! -e "$root/.git/hooks/post-merge" ]; then
    ok "t8c dead .git/hooks shim removed"; else bad "t8c dead shim not removed"; fi

  if ( cd "$root" && "$INSTALL" >/dev/null ); then
    ok "t8d husky reinstall idempotent"; else bad "t8d husky reinstall idempotent"; fi

  # Foreign .husky/post-merge: refuse, leave intact.
  local root2; root2=$(make_repo husk2)
  mkdir -p "$root2/.husky"
  printf '%s\n' '#!/bin/sh' 'echo mine' > "$root2/.husky/post-merge"
  chmod +x "$root2/.husky/post-merge"
  if ( cd "$root2" && "$INSTALL" >/dev/null 2>&1 ); then
    bad "t8e refuse foreign husky hook (did not refuse)"
  elif grep -q 'echo mine' "$root2/.husky/post-merge"; then
    ok "t8e refuse foreign husky hook"; else bad "t8e foreign husky hook clobbered"; fi
}
```

Register it in `main()` between the `t7_install` and `printf` lines:

```bash
  t7_install
  t8_husky_hookspath
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
```

- [ ] **Step 2: Run the test to verify the new case fails**

Run: `bash /Users/ben/workspace/dotfiles/tests/wiki-stage/run.sh`
Expected: t1–t7 pass; t8a/t8b/t8c FAIL (current install writes `.git/hooks/`, never `.husky/`, no exclude, no cleanup). t8d/t8e may pass incidentally. Overall: non-zero exit, `FAIL` count > 0.

- [ ] **Step 3: Rewrite `wiki-stage-install` to be husky-aware**

Replace the entire contents of `bin/.local/bin/wiki-stage-install` with:

```bash
#!/usr/bin/env bash
# Install the wiki-stage post-merge hook into a repo's hooks dir.
# Usage: wiki-stage-install [repo-path]   (default: current repo)
# Worktree-aware (uses --git-common-dir). Husky-aware: a .husky/ dir means git's
# core.hooksPath redirects hook lookup away from .git/hooks/, so the hook is
# installed at .husky/post-merge (husky's _/post-merge wrapper sources it on v9;
# git runs it directly when hooksPath=.husky). The husky hook is kept LOCAL via
# .git/info/exclude and never committed. Refuses to clobber a foreign hook.
set -u

target=${1:-.}
common_dir=$(git -C "$target" rev-parse --git-common-dir 2>/dev/null) || {
  echo "wiki-stage-install: not a git repository: $target" >&2
  exit 1
}
# git --git-common-dir is relative to $target for a normal repo (".git") and
# absolute for a linked worktree; cd into $target first, then into it, to get abs.
common_dir=$(cd "$target" && cd "$common_dir" && pwd) || {
  echo "wiki-stage-install: cannot resolve git dir for $target" >&2
  exit 1
}
repo_root=$(dirname "$common_dir")

# A .husky/ dir is the signal that hooks are redirected away from .git/hooks/.
if [ -d "$repo_root/.husky" ]; then
  hook_dir="$repo_root/.husky"
  hook="$hook_dir/post-merge"
  husky=1
else
  hook_dir="$common_dir/hooks"
  hook="$hook_dir/post-merge"
  husky=0
fi

if [ -e "$hook" ]; then
  if grep -qx 'exec wiki-stage' "$hook" 2>/dev/null; then
    echo "wiki-stage-install: already installed at $hook"
    exit 0
  fi
  echo "wiki-stage-install: refusing to overwrite existing hook: $hook" >&2
  exit 1
fi

mkdir -p "$hook_dir"
if [ "$husky" -eq 1 ]; then
  # Guard: silent no-op for anyone without wiki-stage on PATH.
  if ! printf '%s\n' '#!/usr/bin/env sh' \
        'command -v wiki-stage >/dev/null 2>&1 || exit 0' \
        'exec wiki-stage' > "$hook"; then
    echo "wiki-stage-install: failed to write $hook" >&2; exit 1
  fi
else
  if ! printf '%s\n' '#!/usr/bin/env sh' 'exec wiki-stage' > "$hook"; then
    echo "wiki-stage-install: failed to write $hook" >&2; exit 1
  fi
fi
chmod +x "$hook" || { echo "wiki-stage-install: chmod failed for $hook" >&2; exit 1; }

if [ "$husky" -eq 1 ]; then
  # Keep the hook local: never commit it into the tracked .husky/ dir.
  rel_hook=${hook#"$repo_root"/}
  exclude_file="$common_dir/info/exclude"
  mkdir -p "$common_dir/info"
  if ! grep -qxF "/$rel_hook" "$exclude_file" 2>/dev/null; then
    printf '%s\n' "/$rel_hook" >> "$exclude_file"
  fi
  # Remove a dead wiki-stage shim left in .git/hooks/ (git ignores it under husky).
  legacy="$common_dir/hooks/post-merge"
  if [ "$legacy" != "$hook" ] && [ -f "$legacy" ] \
     && grep -qx 'exec wiki-stage' "$legacy" 2>/dev/null; then
    rm -f "$legacy" && echo "wiki-stage-install: removed dead shim at $legacy"
  fi
fi
echo "wiki-stage-install: installed post-merge hook at $hook"
```

- [ ] **Step 4: Run the full suite to verify all pass**

Run: `bash /Users/ben/workspace/dotfiles/tests/wiki-stage/run.sh`
Expected: `8 ... passed, 0 failed` style summary, exit 0. Specifically t1–t6 (mirror) pass, t7a–t7d (plain `.git/hooks/`) pass, t8a–t8e (husky) pass.

- [ ] **Step 5: Commit the fix**

```bash
cd /Users/ben/workspace/dotfiles
git add bin/.local/bin/wiki-stage-install tests/wiki-stage/run.sh
git commit -m "fix(wiki-stage): install post-merge hook under husky core.hooksPath"
```

---

### Task 2: Repair the live hooks in green-energy-group and ops, verify the mirror

This task touches **uncommitted local state** in two non-dotfiles repos. No commits land in geg/ops; the hooks are excluded.

**Files (uncommitted, local side-effects):**
- `green-energy-group/.husky/post-merge` (+ `info/exclude` entry, dead `.git/hooks/post-merge` removed)
- `ops/.husky/post-merge` (+ `info/exclude` entry, dead `.git/hooks/post-merge` removed)

- [ ] **Step 1: Reinstall in both repos**

```bash
wiki-stage-install /Users/ben/workspace/green-energy-group
wiki-stage-install /Users/ben/workspace/ops
```
Expected: each prints `removed dead shim at .../.git/hooks/post-merge` and `installed post-merge hook at .../.husky/post-merge`.

- [ ] **Step 2: Verify hook placement, body, exclusion, and that the dead shim is gone**

```bash
for r in green-energy-group ops; do
  root="/Users/ben/workspace/$r"
  echo "== $r =="
  cat "$root/.husky/post-merge"
  test -x "$root/.husky/post-merge" && echo "executable: yes"
  grep -qxF '/.husky/post-merge' "$root/.git/info/exclude" && echo "excluded: yes"
  test ! -e "$root/.git/hooks/post-merge" && echo "dead shim: gone"
  ( cd "$root" && git status --porcelain .husky/post-merge )   # expect empty
done
```
Expected per repo: 3-line guarded body; `executable: yes`; `excluded: yes`; `dead shim: gone`; empty `git status` line for the hook (local-only, invisible to git).

- [ ] **Step 3: Confirm husky actually sources our hook (v9 wrapper chain)**

```bash
# geg uses hooksPath=.husky/_ ; confirm the generated wrapper sources user hooks.
grep -l 'post-merge\|\.husky' /Users/ben/workspace/green-energy-group/.husky/_/post-merge
sh -x /Users/ben/workspace/green-energy-group/.husky/_/post-merge </dev/null 2>&1 | grep -i 'post-merge' | head
```
Expected: the `_/post-merge` wrapper references/sources the top-level `.husky/post-merge`. (ops uses `hooksPath=.husky`, so git runs `.husky/post-merge` directly — no wrapper needed.) If the geg wrapper does NOT source `.husky/post-merge`, STOP and report: the husky layout differs from the assumption and the design needs revisiting.

- [ ] **Step 4: Prove the mirror works end-to-end**

```bash
# Direct invocation proves wiki-stage mirrors the full tracked docs/ tree.
( cd /Users/ben/workspace/ops && wiki-stage )
( cd /Users/ben/workspace/green-energy-group && wiki-stage )
# Re-check the drift the investigation found is now closed for raw/.
bash -c '
W=/Users/ben/workspace/wiki/raw
for pair in "green-energy-group:docs" "ops:docs"; do
  r=${pair%%:*}
  echo "== $r raw vs source =="
  echo "src md:  $(find /Users/ben/workspace/$r/docs -name "*.md" | wc -l)"
  echo "raw md:  $(find $W/$r -name "*.md" | wc -l)"
done'
```
Expected: `wiki-stage` runs clean (exit 0). raw md count rises to match (or exceed, since raw retains deleted sources) the source `docs/` md count — the raw backlog is closed. (The separate `okf/` ingest backlog is out of scope.)

- [ ] **Step 5: No commit**

Task 2 produces only local, excluded files. Nothing to stage. Do not commit in geg/ops.

---

## Self-Review

**Spec coverage:**
- Husky-aware install → Task 1 Step 3. ✓
- Guard body → Task 1 Step 3 + t8a. ✓
- Local-only exclude → Task 1 Step 3 + t8b. ✓
- Dead shim cleanup → Task 1 Step 3 + t8c. ✓
- Reinstall in geg/ops → Task 2 Steps 1–2. ✓
- Regression test → Task 1 Steps 1–4. ✓
- Raw backlog self-heal note → Task 2 Step 4. ✓
- Out of scope (okf ingest, team-repo commits) → respected; Task 2 commits nothing in geg/ops. ✓

**Placeholder scan:** none — all code and commands are concrete.

**Type/name consistency:** `husky` flag, `hook`, `hook_dir`, `repo_root`, `common_dir`, `legacy`, `rel_hook`, `exclude_file` consistent across the script. Test asserts the exact guard string written by the script. Detector (`.husky` dir) consistent between script and t8.
