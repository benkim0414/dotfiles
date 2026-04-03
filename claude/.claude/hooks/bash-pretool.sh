#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): consolidated guard for all Bash tool calls.
# Combines worktree-guard, git-main-guard, and commit-guard into a single
# process with a single jq invocation — eliminates 2 redundant bash+jq spawns
# per Bash call.
# Exit 0 = allow (stdout → context). Exit 2 = block (stderr → Claude).
set -euo pipefail

# shellcheck source=../lib/portability.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/portability.sh"

# --- Parse JSON once: extract both session_id and command ---
INPUT=$(cat)
IFS=$'\t' read -r SESSION_ID COMMAND <<< "$(
  printf '%s' "$INPUT" | jq -r '[
    (.session_id // ""),
    (.tool_input.command // "")
  ] | @tsv'
)"

# Per-repo opt-out of PR workflow.
NO_PR=false
[[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]] && NO_PR=true

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
# 2. Git guards — only relevant for git add/commit/push/merge/rebase/cherry-pick
# =====================================================================

# Fast exit for non-git commands (the vast majority of Bash calls).
if [[ ! "$COMMAND" =~ git[[:space:]]+(add|commit|push|merge|rebase|cherry-pick) ]]; then
  exit 0
fi

# --- Block blanket staging commands ---
if [[ "$COMMAND" =~ git[[:space:]]+add[[:space:]]+(-A|--all|--update|-u|\.(\ |$)) ]]; then
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
  if [[ "$cmd_no_msg" =~ git[[:space:]]+commit[[:space:]]+.*(-a(\ |$)|-am(\ |$)|--all) ]]; then
    echo "BLOCKED: Do not use 'git commit -a' — it bypasses selective staging." >&2
    echo "" >&2
    echo "  Stage specific files first, then commit:" >&2
    echo "    git add <file1> <file2>" >&2
    echo "    git commit -m \"type(scope): description\"" >&2
    exit 2
  fi
fi

# --- Compute git context once (shared by all main-branch guards below) ---
BRANCH="" MAIN_BRANCH="main"
if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  REMOTE_HEAD=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
  MAIN_BRANCH="${REMOTE_HEAD#refs/remotes/origin/}"
  MAIN_BRANCH="${MAIN_BRANCH:-main}"
fi

# --- Block commit on main ---
if [[ "$COMMAND" =~ git[[:space:]]+commit && "$BRANCH" == "$MAIN_BRANCH" ]]; then
  echo "BLOCKED: Cannot commit directly on '${MAIN_BRANCH}'." >&2
  echo "Call EnterWorktree() and commit on the isolated feature branch." >&2
  exit 2
fi

# --- Block merge/rebase/cherry-pick on main (enforce PR workflow) ---
# These bypass the PR review process by bringing changes into main locally.
if [[ "$NO_PR" != "true" && "$COMMAND" =~ git[[:space:]]+(merge|rebase|cherry-pick) && "$BRANCH" == "$MAIN_BRANCH" ]]; then
  echo "BLOCKED: Cannot merge/rebase/cherry-pick directly on '${MAIN_BRANCH}'." >&2
  echo "" >&2
  echo "  Push your feature branch and open a PR instead:" >&2
  echo "    git push origin <branch>   # from within the worktree" >&2
  echo "    gh pr create" >&2
  exit 2
fi

# --- Block push to main (checks destination ref, not just current branch) ---
# Allows pushing a feature branch even when HEAD is main (e.g., after ExitWorktree).
if [[ "$NO_PR" != "true" && "$COMMAND" =~ git[[:space:]]+push ]]; then
  block_push=false

  # Case 1: On main with no explicit non-main destination.
  if [[ "$BRANCH" == "$MAIN_BRANCH" ]]; then
    if [[ "$COMMAND" =~ git[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+(origin)[[:space:]]+([^[:space:]]+) ]]; then
      dest="${BASH_REMATCH[3]}"
      # Block only if the explicit refspec targets main (e.g., main or feat:main).
      if [[ "$dest" == "$MAIN_BRANCH" || "$dest" =~ :${MAIN_BRANCH}$ ]]; then
        block_push=true
      fi
      # else: explicit non-main destination while on main → ALLOW (pushes feature branch)
    else
      # No explicit destination: bare `git push` or `git push origin` defaults to main.
      block_push=true
    fi
  fi

  # Case 2: Explicit main destination from any branch (e.g., inside a worktree on
  # a feature branch running `git push origin main` or `git push origin feat:main`).
  if [[ "$block_push" != "true" ]]; then
    if [[ "$COMMAND" =~ git[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+(origin)[[:space:]]+([^[:space:]]+:)?(${MAIN_BRANCH})([[:space:]]|$) ]]; then
      block_push=true
    fi
  fi

  # Case 3: With push.default=upstream the branch's tracked remote may be origin/main
  # (EnterWorktree creates branches that track main). A bare `git push origin <branch>`
  # or `git push` without an explicit same-name refspec would silently redirect there.
  upstream_main_tracking=false
  if [[ "$block_push" != "true" && "$BRANCH" != "$MAIN_BRANCH" ]]; then
    upstream_ref=$(git rev-parse --abbrev-ref "${BRANCH}@{upstream}" 2>/dev/null || true)
    if [[ "$upstream_ref" == "origin/${MAIN_BRANCH}" ]]; then
      # Allow only when an explicit same-name (non-main) refspec is given,
      # e.g. git push origin HEAD:feature or git push origin feature:feature.
      if [[ "$COMMAND" =~ git[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+(origin)[[:space:]]+([^[:space:]]+:[^[:space:]]+) ]]; then
        dest_refspec="${BASH_REMATCH[3]}"
        if [[ "$dest_refspec" =~ :${MAIN_BRANCH}$ ]]; then
          block_push=true  # Explicit push to main via src:main — block.
        fi
        # else: explicit non-main refspec overrides tracking — ALLOW.
      else
        # No explicit refspec: push.default=upstream would silently target origin/main.
        block_push=true
        upstream_main_tracking=true
      fi
    fi
  fi

  if [[ "$block_push" == "true" ]]; then
    echo "BLOCKED: Cannot push directly to '${MAIN_BRANCH}'." >&2
    echo "" >&2
    if [[ "$upstream_main_tracking" == "true" ]]; then
      echo "  Your branch '${BRANCH}' tracks origin/${MAIN_BRANCH}." >&2
      echo "  With push.default=upstream this push would silently target origin/${MAIN_BRANCH}." >&2
      echo "" >&2
      echo "  Use an explicit refspec to create a new remote branch instead:" >&2
      echo "    git push origin HEAD:${BRANCH}" >&2
    else
      echo "  Push to your feature branch: git push origin <branch>:<branch>" >&2
      echo "  Then open a PR:              gh pr create" >&2
    fi
    exit 2
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
