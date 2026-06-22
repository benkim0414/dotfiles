# Wiki Stage Docs Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically mirror a repo's finalized `docs/` tree into `~/workspace/wiki/raw/<repo>/` on merge to `main`, idempotently, for later manual `/ingest` into the wiki's `okf/` pages.

**Architecture:** A repo-agnostic `wiki-stage` bash script does an idempotent, content-hash-skipped, tracked-only, copy/update-only (never delete) file mirror. A `wiki-stage-install` script drops a one-line `post-merge` shim into a repo's hooks dir (worktree-aware, refuses to clobber foreign hooks). dotfiles is wired first. Ingestion stays a separate manual step.

**Tech Stack:** POSIX-ish bash, git plumbing (`rev-parse --git-common-dir`, `ls-files -z`), `cmp`, shellcheck. Tests are a self-contained bash harness using temp repos + a `WIKI_STAGE_DEST_ROOT` override so the real wiki is never touched.

---

## File Structure

```
bin/.local/bin/wiki-stage           # idempotent mirror + manual entrypoint (Task 1)
bin/.local/bin/wiki-stage-install   # per-repo post-merge shim installer (Task 2)
tests/wiki-stage/run.sh             # bash test harness, NOT stowed (Tasks 1-2)
CLAUDE.md                           # setup note (Task 3)
```

Spec: `docs/superpowers/specs/2026-06-22-wiki-stage-docs-mirror-design.md`.

Notes:
- `tests/` is a repo-root dir, never passed to `stow`, so the harness never symlinks into `~/.local/bin`.
- Content compare uses `cmp -s` (byte-exact) — equivalent to the spec's "content hash differs", simpler, no temp hashing.
- `wiki-stage` must never fail a merge: it exits 0 on every guard and on per-file errors.

---

## Task 1: `wiki-stage` mirror script

**Files:**
- Create: `bin/.local/bin/wiki-stage`
- Create: `tests/wiki-stage/run.sh`

- [ ] **Step 1: Write the failing test harness**

Create `tests/wiki-stage/run.sh`:

```bash
#!/usr/bin/env bash
# Test harness for wiki-stage and wiki-stage-install.
# Run: bash tests/wiki-stage/run.sh
set -u

DOTFILES=$(cd "$(dirname "$0")/../.." && pwd)
STAGE="$DOTFILES/bin/.local/bin/wiki-stage"
INSTALL="$DOTFILES/bin/.local/bin/wiki-stage-install"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# Make a throwaway git repo named $1 under $TMP with a committed docs/ tree.
make_repo() {
  local name=$1 root="$TMP/$1"
  mkdir -p "$root"
  git -C "$root" init -q
  git -C "$root" config user.email t@t.t
  git -C "$root" config user.name t
  mkdir -p "$root/docs/superpowers/specs"
  printf 'spec body\n' > "$root/docs/superpowers/specs/a.md"
  git -C "$root" add docs/superpowers/specs/a.md
  git -C "$root" commit -q -m init
  printf '%s' "$root"
}

t1_basic_mirror() {
  local root; root=$(make_repo myrepo)
  ( cd "$root" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  local dest="$WIKI/raw/myrepo/superpowers/specs/a.md"
  if [ -f "$dest" ] && cmp -s "$root/docs/superpowers/specs/a.md" "$dest"; then
    ok "t1 basic mirror"; else bad "t1 basic mirror ($dest)"; fi
}

t2_idempotent() {
  local root; root=$(make_repo idem)
  ( cd "$root" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  local dest="$WIKI/raw/idem/superpowers/specs/a.md"
  touch -t 200001010000 "$dest"          # mark old; skip must preserve mtime
  ( cd "$root" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  local n; n=$(find "$WIKI/raw/idem" -type f | wc -l | tr -d ' ')
  local stamp; stamp=$(date -r "$dest" +%Y 2>/dev/null || stat -c %y "$dest" | cut -c1-4)
  if [ "$n" = "1" ] && [ "$stamp" = "2000" ]; then
    ok "t2 idempotent (no dup, skipped)"; else bad "t2 idempotent (n=$n stamp=$stamp)"; fi
}

t3_changed_updates() {
  local root; root=$(make_repo chg)
  ( cd "$root" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  printf 'new body\n' > "$root/docs/superpowers/specs/a.md"
  ( cd "$root" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  local dest="$WIKI/raw/chg/superpowers/specs/a.md"
  if cmp -s "$root/docs/superpowers/specs/a.md" "$dest"; then
    ok "t3 changed file updates in place"; else bad "t3 changed file"; fi
}

t4_untracked_skipped() {
  local root; root=$(make_repo untr)
  printf 'wip\n' > "$root/docs/superpowers/specs/wip.md"   # never git-added
  ( cd "$root" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  if [ ! -e "$WIKI/raw/untr/superpowers/specs/wip.md" ]; then
    ok "t4 untracked not mirrored"; else bad "t4 untracked leaked"; fi
}

t5_worktree_canonical_name() {
  local root; root=$(make_repo canon)
  git -C "$root" worktree add -q -b feat "$TMP/canon-wt" >/dev/null 2>&1
  ( cd "$TMP/canon-wt" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  # Must land under raw/canon (main repo basename), not raw/canon-wt.
  if [ -f "$WIKI/raw/canon/superpowers/specs/a.md" ] && [ ! -d "$WIKI/raw/canon-wt" ]; then
    ok "t5 worktree resolves canonical repo name"; else bad "t5 worktree name"; fi
}

t6_deleted_source_retained() {
  local root; root=$(make_repo del)
  ( cd "$root" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  git -C "$root" rm -q docs/superpowers/specs/a.md
  git -C "$root" commit -q -m drop
  ( cd "$root" && WIKI_STAGE_DEST_ROOT="$WIKI" "$STAGE" )
  if [ -f "$WIKI/raw/del/superpowers/specs/a.md" ]; then
    ok "t6 deleted source retained in raw"; else bad "t6 deleted source"; fi
}

main() {
  TMP=$(mktemp -d)
  WIKI="$TMP/wiki"; mkdir -p "$WIKI"
  trap 'rm -rf "$TMP"' EXIT
  t1_basic_mirror
  t2_idempotent
  t3_changed_updates
  t4_untracked_skipped
  t5_worktree_canonical_name
  t6_deleted_source_retained
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
main "$@"
```

- [ ] **Step 2: Run the harness to verify it fails**

Run: `bash tests/wiki-stage/run.sh; echo "exit=$?"`
Expected: FAIL — `wiki-stage` does not exist yet, every test reports FAIL, `exit=1`.

- [ ] **Step 3: Write `wiki-stage`**

Create `bin/.local/bin/wiki-stage`:

```bash
#!/usr/bin/env bash
# Mirror a repo's tracked docs/ tree into <wiki>/raw/<repo>/.
# Idempotent: copies only new or content-changed files; never deletes.
# Safe anytime; also the manual/backfill entrypoint. Called from post-merge
# hooks, so it MUST NOT fail a merge: exits 0 on every guard and per-file error.
set -u

# Canonical repo identity, worktree-independent.
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
common_dir=$(cd "$common_dir" 2>/dev/null && pwd) || exit 0
repo_root=$(dirname "$common_dir")
repo_name=$(basename "$repo_root")

docs_root="$repo_root/docs"
[ -d "$docs_root" ] || exit 0

wiki_root="${WIKI_STAGE_DEST_ROOT:-$HOME/workspace/wiki}"
[ -d "$wiki_root" ] || exit 0
dest_base="$wiki_root/raw/$repo_name"

# Tracked files under docs/, NUL-delimited for safe paths.
while IFS= read -r -d '' rel; do
  sub=${rel#docs/}                 # strip leading docs/
  src="$repo_root/$rel"
  dest="$dest_base/$sub"
  [ -f "$src" ] || continue        # tracked but absent in worktree -> never delete dest
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    continue                       # byte-identical -> skip
  fi
  if ! mkdir -p "$(dirname "$dest")"; then
    echo "wiki-stage: mkdir failed for $dest" >&2; continue
  fi
  if ! cp -p "$src" "$dest"; then
    echo "wiki-stage: copy failed for $src" >&2; continue
  fi
done < <(git -C "$repo_root" ls-files -z -- docs/)

exit 0
```

Then make it executable:

Run: `chmod +x bin/.local/bin/wiki-stage`

- [ ] **Step 4: Run the harness to verify it passes**

Run: `bash tests/wiki-stage/run.sh; echo "exit=$?"`
Expected: PASS — `6 passed, 0 failed`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add bin/.local/bin/wiki-stage tests/wiki-stage/run.sh
git commit -m "feat(wiki-stage): idempotent docs mirror into wiki raw/

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `wiki-stage-install` shim installer

**Files:**
- Create: `bin/.local/bin/wiki-stage-install`
- Modify: `tests/wiki-stage/run.sh` (add `t7`, call it in `main`)

- [ ] **Step 1: Add the failing install test**

In `tests/wiki-stage/run.sh`, add this function immediately after `t6_deleted_source_retained`:

```bash
t7_install() {
  local root; root=$(make_repo inst)
  # Fresh repo: install writes the shim.
  ( cd "$root" && "$INSTALL" >/dev/null )
  local hook="$root/.git/hooks/post-merge"
  if [ -x "$hook" ] && grep -q 'exec wiki-stage' "$hook"; then
    ok "t7a install writes shim"; else bad "t7a install writes shim"; fi
  # Re-run: idempotent, exits 0.
  if ( cd "$root" && "$INSTALL" >/dev/null ); then
    ok "t7b reinstall idempotent"; else bad "t7b reinstall idempotent"; fi
  # Foreign hook: refuse, leave it intact.
  local root2; root2=$(make_repo inst2)
  printf '#!/bin/sh\necho mine\n' > "$root2/.git/hooks/post-merge"
  chmod +x "$root2/.git/hooks/post-merge"
  if ( cd "$root2" && "$INSTALL" >/dev/null 2>&1 ); then
    bad "t7c refuse foreign hook (did not refuse)"
  elif grep -q 'echo mine' "$root2/.git/hooks/post-merge"; then
    ok "t7c refuse foreign hook"; else bad "t7c foreign hook clobbered"; fi
}
```

And add `t7_install` to `main`, immediately after the `t6_deleted_source_retained` line:

```bash
  t6_deleted_source_retained
  t7_install
```

- [ ] **Step 2: Run the harness to verify the new test fails**

Run: `bash tests/wiki-stage/run.sh; echo "exit=$?"`
Expected: FAIL — `t7a`/`t7b`/`t7c` fail (`wiki-stage-install` missing), `exit=1`.

- [ ] **Step 3: Write `wiki-stage-install`**

Create `bin/.local/bin/wiki-stage-install`:

```bash
#!/usr/bin/env bash
# Install the wiki-stage post-merge shim into a repo's hooks dir.
# Usage: wiki-stage-install [repo-path]   (default: current repo)
# Worktree-aware (uses --git-common-dir). Refuses to clobber a foreign hook.
set -u

target=${1:-.}
common_dir=$(git -C "$target" rev-parse --git-common-dir 2>/dev/null) || {
  echo "wiki-stage-install: not a git repository: $target" >&2
  exit 1
}
common_dir=$(cd "$target" && cd "$common_dir" && pwd) || {
  echo "wiki-stage-install: cannot resolve git dir for $target" >&2
  exit 1
}
hooks_dir="$common_dir/hooks"
hook="$hooks_dir/post-merge"

if [ -e "$hook" ]; then
  if grep -q 'exec wiki-stage' "$hook" 2>/dev/null; then
    echo "wiki-stage-install: already installed at $hook"
    exit 0
  fi
  echo "wiki-stage-install: refusing to overwrite existing hook: $hook" >&2
  exit 1
fi

mkdir -p "$hooks_dir"
printf '%s\n' '#!/usr/bin/env sh' 'exec wiki-stage' > "$hook"
chmod +x "$hook"
echo "wiki-stage-install: installed post-merge shim at $hook"
```

Then make it executable:

Run: `chmod +x bin/.local/bin/wiki-stage-install`

- [ ] **Step 4: Run the harness to verify it passes**

Run: `bash tests/wiki-stage/run.sh; echo "exit=$?"`
Expected: PASS — `9 passed, 0 failed`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add bin/.local/bin/wiki-stage-install tests/wiki-stage/run.sh
git commit -m "feat(wiki-stage): add post-merge shim installer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: shellcheck, wire dotfiles, document

**Files:**
- Modify: `CLAUDE.md` (add a setup note under the appropriate section)

- [ ] **Step 1: shellcheck both scripts**

Run: `shellcheck bin/.local/bin/wiki-stage bin/.local/bin/wiki-stage-install; echo "exit=$?"`
Expected: PASS — no output, `exit=0`. If shellcheck flags an issue, fix it in the script and re-run until clean (do not silence with a blanket `disable`).

- [ ] **Step 2: Wire the dotfiles repo (local, not committed)**

The `post-merge` shim lives under `.git/hooks/` and is not tracked, so this is a one-time local setup action — there is nothing to commit from this step.

Run: `bin/.local/bin/wiki-stage-install`
Expected: `wiki-stage-install: installed post-merge shim at .../dotfiles/.git/hooks/post-merge` (note: when run from this worktree, `--git-common-dir` resolves to the main dotfiles `.git`, so the hook installs on the canonical repo, which is correct).

Verify:
Run: `cat "$(git rev-parse --git-common-dir)/hooks/post-merge"`
Expected:
```
#!/usr/bin/env sh
exec wiki-stage
```

- [ ] **Step 3: Add the setup note to `CLAUDE.md`**

In `CLAUDE.md`, add a new top-level section documenting the staging tool. Insert it after the `# Secrets` section and before `# Stow gotchas`:

```markdown
# Wiki staging

Generated plugin docs (`docs/superpowers/{specs,plans}/`, `docs/solutions/`) are
mirrored into `~/workspace/wiki/raw/<repo>/` for later `/ingest` into the wiki's
`okf/` knowledge pages.

- `wiki-stage` -- idempotent mirror of a repo's tracked `docs/` tree into
  `~/workspace/wiki/raw/<repo>/`. Content-hash skip, never deletes, exits 0 on
  every guard. Safe to run manually anytime (also backfills).
- `wiki-stage-install` -- installs a `post-merge` shim into a repo so staging
  fires automatically when docs merge to `main`. Run once per repo to wire it;
  refuses to clobber an existing foreign hook.
- Staging is copy-only: it never commits or pushes the wiki. Ingestion into
  `okf/` stays a separate manual step (the wiki's `/ingest` skill).

Design: `docs/superpowers/specs/2026-06-22-wiki-stage-docs-mirror-design.md`.
```

- [ ] **Step 4: Verify the docs build/read cleanly**

Run: `git diff --stat`
Expected: shows `CLAUDE.md` modified (the only tracked change from this task; the hook install in Step 2 is untracked and produces no diff).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(wiki-stage): document staging tool setup

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Stage-only scope -> Tasks 1-2 (no ingest, no wiki git writes). ✓
- `wiki-stage` behavior (canonical name, docs_root, tracked-only, hash skip, never delete, exit 0 guards) -> Task 1 Step 3 + tests t1-t6. ✓
- `WIKI_STAGE_DEST_ROOT` override -> Task 1 Step 3, used by all tests. ✓
- `post-merge` shim + worktree-aware installer + refuse-foreign -> Task 2 + t7. ✓
- Trigger via per-repo shim, dotfiles wired first -> Task 3 Step 2. ✓
- Whole `docs/` tree (no config) -> `git ls-files -- docs/` in Task 1 Step 3. ✓
- Tests at repo-root `tests/wiki-stage/run.sh`, not stowed -> created in Tasks 1-2. ✓
- shellcheck clean -> Task 3 Step 1. ✓
- Acceptance criteria (mirror, idempotent, untracked/deleted rules, merge triggers, tests pass) -> covered by t1-t7 + Task 3. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type/name consistency:** `WIKI_STAGE_DEST_ROOT`, `wiki-stage`, `wiki-stage-install`, `exec wiki-stage` shim text, `raw/<repo>/<sub>` mapping, and `cmp -s` skip are used identically across the spec, scripts, and tests. ✓
