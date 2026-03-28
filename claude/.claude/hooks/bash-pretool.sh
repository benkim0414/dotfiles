#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): consolidated guard for all Bash tool calls.
# Combines worktree-guard, git-main-guard, and commit-guard into a single
# process with a single jq invocation — eliminates 2 redundant bash+jq spawns
# per Bash call.
# Exit 0 = allow (stdout → context). Exit 2 = block (stderr → Claude).
set -euo pipefail

# Portable fallbacks for macOS (system bash 3.2 lacks EPOCHSECONDS; BSD stat
# uses -f %m instead of GNU -c %Y).
: "${EPOCHSECONDS:=$(date +%s)}"
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# --- Parse JSON once: extract both session_id and command ---
INPUT=$(cat)
IFS=$'\t' read -r SESSION_ID COMMAND <<< "$(
  printf '%s' "$INPUT" | jq -r '[
    (.session_id // ""),
    (.tool_input.command // "")
  ] | @tsv'
)"

# =====================================================================
# 1. Worktree guard — block file-touching tools until EnterWorktree()
# =====================================================================

# Reject anything that isn't a UUID to prevent unexpected jq output in file paths.
[[ "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || SESSION_ID=""

if [[ -n "$SESSION_ID" ]]; then
  PENDING="$HOME/.claude/session-worktrees/pending-${SESSION_ID}"
  if [[ -f "$PENDING" ]]; then
    # Self-healing: if already in a linked worktree (PostToolUse may not have
    # fired for built-in tools), clear the stale file and pass through.
    GIT_ABS=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
    GIT_COM=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd || true)
    if [[ -n "$GIT_ABS" && -n "$GIT_COM" && "$GIT_ABS" != "$GIT_COM" ]]; then
      rm -f "$PENDING"
    else
      echo "BLOCKED: This session requires an isolated git worktree before file edits." >&2
      echo "" >&2
      echo "Call EnterWorktree() now — it creates an isolated branch off HEAD automatically." >&2
      echo "File-editing tools are blocked until the worktree is entered." >&2
      echo "" >&2
      echo "  Emergency escape: rm \"${PENDING}\"" >&2
      exit 2
    fi
  fi
fi

# =====================================================================
# 2. Git guards — only relevant for git add/commit/push commands
# =====================================================================

# Fast exit for non-git commands (the vast majority of Bash calls).
if [[ ! "$COMMAND" =~ git[[:space:]]+(add|commit|push) ]]; then
  exit 0
fi

# --- Block blanket staging commands ---
if echo "$COMMAND" | grep -qE 'git\s+add\s+(-A|--all|--update|-u|\.(\s|$))'; then
  echo "BLOCKED: Stage specific files instead of everything." >&2
  echo "" >&2
  echo "  Use: git add <file1> <file2> ..." >&2
  echo "  Not:  git add -A / --all / --update / ." >&2
  echo "" >&2
  echo "  Stage only the files for ONE logical change, commit, then repeat." >&2
  exit 2
fi

# --- Block git commit -a (bypasses selective staging) ---
if [[ "$COMMAND" =~ git[[:space:]]+commit ]]; then
  # Strip the -m argument content to avoid false positives where -a appears
  # inside the commit message string (e.g., git commit -m "add -a flag support").
  cmd_no_msg=$(printf '%s' "$COMMAND" | sed 's/ -m ["'"'"'$].*//')
  if echo "$cmd_no_msg" | grep -qE 'git\s+commit\s+.*(-a(\s|$)|-am(\s|$)|--all)'; then
    echo "BLOCKED: Do not use 'git commit -a' — it bypasses selective staging." >&2
    echo "" >&2
    echo "  Stage specific files first, then commit:" >&2
    echo "    git add <file1> <file2>" >&2
    echo "    git commit -m \"type(scope): description\"" >&2
    exit 2
  fi
fi

# --- Main branch guard (git commit/push only) ---
if [[ "$COMMAND" =~ (^|[,\;\&\|][[:space:]]*)git[[:space:]]+(commit|push) ]]; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    REMOTE_HEAD=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
    MAIN_BRANCH="${REMOTE_HEAD#refs/remotes/origin/}"
    MAIN_BRANCH="${MAIN_BRANCH:-main}"
    if [[ "$BRANCH" == "$MAIN_BRANCH" ]]; then
      echo "BLOCKED: Cannot commit/push directly on '${MAIN_BRANCH}'." >&2
      echo "Create a feature branch first:" >&2
      echo "  git checkout -b <type>/<scope>-<description>" >&2
      exit 2
    fi
  fi
fi

# --- Inject staged file context at commit time ---
if [[ ! "$COMMAND" =~ git[[:space:]]+commit ]]; then
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

staged=$(git diff --cached --name-only 2>/dev/null)
if [[ -z "$staged" ]]; then
  exit 0
fi

file_count=$(echo "$staged" | wc -l)
dirs=$(echo "$staged" | grep '/' | cut -d/ -f1 | sort -u | tr '\n' ', ' | sed 's/,$//')

# Collect known scopes from recent history — cached with 60-second TTL.
repo_path=$(git rev-parse --show-toplevel 2>/dev/null || true)
repo_key=${repo_path//[^a-zA-Z0-9_]/_}
cache_dir="${XDG_RUNTIME_DIR:-$HOME/.cache/claude}"
mkdir -p "$cache_dir" 2>/dev/null || true
scope_cache="${cache_dir}/commit-scopes-${repo_key}"
scope_age=999
if [[ -f "$scope_cache" ]]; then
  scope_age=$(( EPOCHSECONDS - $(file_mtime "$scope_cache") ))
fi
if (( scope_age > 60 )); then
  known_scopes=$(git log --format='%s' -200 2>/dev/null \
    | sed -n 's/^[a-z]*(\([^)]*\)).*/\1/p' \
    | sort -u | tr '\n' ', ' | sed 's/,$//' || true)
  printf '%s' "$known_scopes" > "$scope_cache" 2>/dev/null || true
else
  known_scopes=$(cat "$scope_cache" 2>/dev/null || true)
fi

echo "[commit-guard] Staged files (${file_count}):"
echo "$staged" | sed 's/^/  /'
echo ""
if [[ -n "$dirs" ]]; then
  echo "[commit-guard] Top-level directories: ${dirs}"
fi
if [[ -n "$known_scopes" ]]; then
  echo "[commit-guard] Known scopes: ${known_scopes}"
fi
echo "[commit-guard] IMPORTANT: Use a known scope. Verify this is ONE logical change."

exit 0
