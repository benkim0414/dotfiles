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
  git -C "$root" config core.hooksPath /dev/null   # isolate from global git hooks
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

t7_install() {
  local root; root=$(make_repo inst)
  # Fresh repo: install writes the shim.
  ( cd "$root" && "$INSTALL" >/dev/null )
  local hook="$root/.git/hooks/post-merge"
  if [ -x "$hook" ] && diff -q <(printf '#!/usr/bin/env sh\nexec wiki-stage\n') "$hook" >/dev/null; then
    ok "t7a install writes exact shim"; else bad "t7a install writes exact shim"; fi
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

  # t7d: explicit path arg, invoked from a different cwd.
  local root3; root3=$(make_repo inst3)
  ( cd "$TMP" && "$INSTALL" "$root3" >/dev/null )
  if [ -x "$root3/.git/hooks/post-merge" ] && grep -qx 'exec wiki-stage' "$root3/.git/hooks/post-merge"; then
    ok "t7d install via explicit path arg"; else bad "t7d explicit path arg"; fi
}

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
  t7_install
  t8_husky_hookspath
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
main "$@"
