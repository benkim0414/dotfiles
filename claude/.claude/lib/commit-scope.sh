#!/usr/bin/env bash
# Signal-driven commit-scope validation. Repo-agnostic.
#
# Four signals (computed against the current repo's filesystem + git log):
#   S1 universal filesystem container name (with history escape)
#   S2 repo basename (no history escape)
#   S3 staged-path segment match (with history escape, +s plural inflection)
#   S4 new-scope soft advisory (emitted by the hook, not by this lib)
#
# Pure POSIX-bash. No external state. Safe to source repeatedly.

# S1: filesystem-convention container names. Stable across codebases for decades.
# These are container directory names, NOT framework names. Do not add artifact-
# type or framework names here -- those get caught by S3 (path-segment match).
CONTAINER_NAMES=(
  docs doc src lib bin scripts script
  tests test assets static public
  vendor build dist target
  packages apps
)

# --- Private helpers --------------------------------------------------------

_repo_basename() {
  if [[ -n "${COMMIT_SCOPE_REPO_NAME:-}" ]]; then
    echo "$COMMIT_SCOPE_REPO_NAME"
    return 0
  fi
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  basename "$top"
}

_known_scopes() {
  if [[ -n "${COMMIT_SCOPE_KNOWN_OVERRIDE:-}" ]]; then
    echo "$COMMIT_SCOPE_KNOWN_OVERRIDE" | tr ',' '\n'
    return 0
  fi
  git log --format='%s' -100 2>/dev/null \
    | awk -F'[()]' '/^[a-z]+\(/ {print $2}' \
    | sort -u
}

_is_container() {
  local s="$1" c
  for c in "${CONTAINER_NAMES[@]}"; do
    [[ "$s" == "$c" ]] && return 0
  done
  return 1
}

_in_known_scopes() {
  local scope="$1"
  _known_scopes | grep -qxF "$scope"
}

_seg_matches_scope() {
  local scope="$1" seg="$2"
  [[ "$scope" == "$seg" ]] && return 0
  [[ "${scope}s" == "$seg" ]] && return 0
  [[ "$scope" == "${seg}s" ]] && return 0
  return 1
}

_path_segments() {
  local staged="$1"
  echo "$staged" | tr '/' '\n' | sed '/^$/d' | sed 's|\.md$||' | sort -u
}

# --- Public API -------------------------------------------------------------

# is_banned_scope <scope> [<staged-files>]
# Exit 0 = banned, 1 = ok.
is_banned_scope() {
  local scope="$1" staged="${2:-}"

  # S1: universal container, with history escape
  if _is_container "$scope" && ! _in_known_scopes "$scope"; then
    return 0
  fi

  # S2: repo basename, no history escape
  local repo
  if repo=$(_repo_basename); then
    [[ "$scope" == "$repo" ]] && return 0
  fi

  # S3: staged path segment with history escape + plural inflection
  if [[ -n "$staged" ]] && ! _in_known_scopes "$scope"; then
    local seg
    while IFS= read -r seg; do
      [[ -z "$seg" ]] && continue
      if _seg_matches_scope "$scope" "$seg"; then
        return 0
      fi
    done < <(_path_segments "$staged")
  fi

  return 1
}

# suggest_scope <staged-files>
# Echo candidate scope (empty if none).
suggest_scope() {
  local staged="$1"
  local count
  count=$(echo "$staged" | grep -c '.' || true)
  local candidate=""

  # Step 1: single file with date-prefixed slug
  if (( count == 1 )); then
    local base
    base=$(basename "$staged")
    if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-(.+)\.md$ ]]; then
      candidate="${BASH_REMATCH[1]}"
      candidate="${candidate%-design}"
      candidate="${candidate%-plan}"
    fi
  fi

  # Step 2: single .md file under nested path; walk deepest-first
  if [[ -z "$candidate" ]] && (( count == 1 )) && [[ "$staged" == *.md ]]; then
    local dir seg
    dir=$(dirname "$staged")
    while [[ "$dir" != "." && "$dir" != "/" && "$dir" != "" ]]; do
      seg=$(basename "$dir")
      if ! _is_container "$seg"; then
        candidate="$seg"
        break
      fi
      dir=$(dirname "$dir")
    done
  fi

  # Step 3: single top-level non-container dir
  if [[ -z "$candidate" ]]; then
    local top
    top=$(echo "$staged" | cut -d/ -f1 | sort -u)
    if [[ "$(echo "$top" | wc -l)" -eq 1 ]] && ! _is_container "$top"; then
      candidate="$top"
    fi
  fi

  [[ -z "$candidate" ]] && return 0

  # Step 4-5: match against known scopes (longest match)
  local k best="" best_len=0
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if [[ "$candidate" == "$k" ]] \
        || [[ "$candidate" == "${k}-"* ]] \
        || [[ "$candidate" == *"-${k}-"* ]] \
        || [[ "$candidate" == *"-${k}" ]]; then
      if (( ${#k} > best_len )); then
        best="$k"
        best_len=${#k}
      fi
    fi
  done < <(_known_scopes)

  if [[ -n "$best" ]]; then
    echo "$best"
  else
    # Step 6: echo bare candidate
    echo "$candidate"
  fi
}
