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
