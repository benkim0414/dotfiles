#!/usr/bin/env bash
# commit-guard.sh — guard git Bash calls: commit atomicity, scope, no commit on main.
#
# Event:   PreToolUse
# Matcher: Bash
# Exit:    0 = allow (warnings → stdout/context); 2 = block (stderr → Claude)
#
# Blocks commit on main, enforces staging atomicity (no `git add -A`, no
# `git commit -a`), and emits non-blocking commit-scope warnings via
# lib/commit-scope.sh -- all with a single jq invocation. Worktree isolation
# for file edits is handled by the dedicated worktree-guard.sh hook
# (matcher: Write|Edit|NotebookEdit).
set -euo pipefail

# --- Read stdin once; fast-exit for non-git commands ---
INPUT=$(cat)

# --- CWD health check (pure builtins, ~0.3ms) ---
# NOTE: The Bash tool harness validates CWD existence before running hooks.
# If the CWD is a deleted directory, the harness rejects with "Error: Path
# ... does not exist" and this check never executes.  This guard catches the
# rarer case where the directory exists but is in an inconsistent state.
# When stuck in a deleted CWD, the user must escape via: ! cd <project-root>
if [[ ! -d "$PWD" ]]; then
  # Cold path (deleted CWD): lazily source session.sh for cwd_repo_hint so the
  # hot path (~90% of Bash calls) stays lib-free.
  # shellcheck source=../lib/session.sh
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"
  repo_hint=$(cwd_repo_hint)
  {
    echo "BLOCKED: Shell CWD no longer exists: $PWD"
    echo ""
    if [[ -n "$repo_hint" ]]; then
      echo "  The worktree was deleted. Type at the Claude Code prompt:"
      echo "    ! cd \"$repo_hint\""
      echo "  Then retry your command."
    else
      echo "  Type at the Claude Code prompt:"
      echo "    ! cd <project-root>"
      echo "  Then retry your command."
    fi
  } >&2
  exit 2
fi

# Most Bash calls never mention git — skip those without spawning jq or
# sourcing libs. Deliberately matches `git ` anywhere in the payload rather
# than only at the start of the command: `cd x && git add -A` and
# `time git commit -am ...` must reach the guards below. A payload that
# merely mentions git in prose costs one extra jq fork and then falls
# through, because every guard tests the parsed .tool_input.command.
if [[ "$INPUT" != *'git '* ]]; then
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

# Strip from the message argument onward, so a banned form quoted inside a
# commit message is not mistaken for a command. Two passes: plain ` -m `
# drops the whole ` -m "..."` tail (nothing downstream looks for a bare -m),
# and the combined short form ` -am ` drops only the message, KEEPING the
# `-am` token itself -- the -a/-am detection below matches against this same
# cmd_no_msg and needs `-am` still visible. `git commit -am "mentions git
# add"` must neither read back as a real `git add` nor lose its `-am` flag.
# Known limitation: this also hides anything chained AFTER the message, so
# `git commit -m "x" && git add -A` is not caught. The common shape puts
# staging first (`git add -A && git commit -m "x"`), which is still caught.
cmd_no_msg=$(printf '%s' "$COMMAND" \
  | sed -e 's/ -m ["'"'"'$].*//' -e 's/\( -am\) ["'"'"'$].*/\1/')

# =====================================================================
# Git guards — only relevant for git add/commit/push/merge/rebase/cherry-pick
# =====================================================================
# NOTE: Worktree isolation for file-editing tools (Write, Edit,
# NotebookEdit) is enforced by the dedicated worktree-guard.sh hook.
# This hook only enforces git-command guards (no commit on main).

# Fast exit for non-git commands (the vast majority of Bash calls). This is
# a "does this text MENTION one of these verbs" pre-filter, not a "does this
# command DO X" decision, so it deliberately matches raw $COMMAND rather
# than cmd_no_msg: under-matching here would silently skip every guard
# below for a real git action, while over-matching only costs a few more
# regex tests that themselves match cmd_no_msg correctly.
if [[ ! "$COMMAND" =~ git[[:space:]]+(add|commit|push|merge|rebase|cherry-pick) ]]; then
  exit 0
fi

# --- Block blanket staging commands ---
if [[ "$cmd_no_msg" =~ git[[:space:]]+add[[:space:]]+(-A|--all|--update|-u|\.(\ |$)) ]]; then
  echo "BLOCKED: Stage specific files instead of everything." >&2
  echo "" >&2
  echo "  Use: git add <file1> <file2> ..." >&2
  echo "  Not:  git add -A / --all / --update / ." >&2
  echo "" >&2
  echo "  Stage only the files for ONE logical change, commit, then repeat." >&2
  exit 2
fi

# Allowed git-add — no branch checks needed. "Does this command run
# git add" is a DO-check, so it matches cmd_no_msg: a `git commit -am`
# whose MESSAGE merely mentions "git add" must not hit this early exit
# and skip the -a guard below.
[[ "$cmd_no_msg" =~ git[[:space:]]+add ]] && exit 0

# --- Block git commit -a (bypasses selective staging) ---
# DO-check ("is this a commit"), so it gates on cmd_no_msg like the check
# inside it, not on raw $COMMAND.
if [[ "$cmd_no_msg" =~ git[[:space:]]+commit ]]; then
  # cmd_no_msg (hoisted above) already strips the -m argument content to
  # avoid false positives where -a appears inside the commit message string
  # (e.g., git commit -m "add -a flag support").
  if [[ "$cmd_no_msg" =~ git[[:space:]]+commit[[:space:]]+.*(-a(\ |$)|-am(\ |$)|--all) ]]; then
    echo "BLOCKED: Do not use 'git commit -a' — it bypasses selective staging." >&2
    echo "" >&2
    echo "  Stage specific files first, then commit:" >&2
    echo "    git add <file1> <file2>" >&2
    echo "    git commit -m \"type(scope): description\"" >&2
    exit 2
  fi
fi

# --- Compute git context once (shared by the main-branch guard below) ---
BRANCH="" MAIN_BRANCH="main"
if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  REMOTE_HEAD=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
  MAIN_BRANCH="${REMOTE_HEAD#refs/remotes/origin/}"
  MAIN_BRANCH="${MAIN_BRANCH:-main}"
fi

# --- Block commit on main ---
# DO-check + a blocking exit, so it must not fire from message text (e.g. a
# `git merge ... -m "...git commit..."` merge-commit message) -- match
# cmd_no_msg.
if [[ "$cmd_no_msg" =~ git[[:space:]]+commit && "$BRANCH" == "$MAIN_BRANCH" ]]; then
  echo "BLOCKED: Cannot commit directly on '${MAIN_BRANCH}'." >&2
  echo "Call EnterWorktree() and commit on the isolated feature branch." >&2
  exit 2
fi

# --- Inject staged file context at commit time ---
# DO-check gating whether this is actually a commit; a non-commit command
# (e.g. a merge) whose message happens to mention "commit" must not trigger
# commit-time context injection -- match cmd_no_msg.
if [[ ! "$cmd_no_msg" =~ git[[:space:]]+commit ]]; then
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
# Source session.sh (provides emit_context + portability helpers) and
# commit-scope.sh (provides is_banned_scope + suggest_scope).
# shellcheck source=../lib/session.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"
# shellcheck source=../lib/commit-scope.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/commit-scope.sh"

# Parse declared scope from commit message (only scoped form counts).
# Deliberate exception to the cmd_no_msg rule used everywhere else in this
# file: this is the one place that WANTS the message text, so it must read
# raw $COMMAND -- cmd_no_msg has already stripped the very content being
# extracted here.
scope_msg=""
msg_pat_dquote='-m[[:space:]]+"([^"]*)"'
msg_pat_squote="-m[[:space:]]+'([^']*)'"
if [[ "$COMMAND" =~ $msg_pat_dquote ]]; then
  scope_msg="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ $msg_pat_squote ]]; then
  scope_msg="${BASH_REMATCH[1]}"
fi

declared_scope=""
scoped_pat='^[a-z]+\(([^)]+)\):'
if [[ "$scope_msg" =~ $scoped_pat ]]; then
  declared_scope="${BASH_REMATCH[1]}"
fi

# Banned-scope emit (S1/S2/S3 via is_banned_scope) — separate from staged-context.
if [[ -n "$declared_scope" ]] && is_banned_scope "$declared_scope" "$staged"; then
  emit_context "PreToolUse" "Scope check: scope='${declared_scope}' is BANNED (filesystem container, repo basename, or path-segment match). Scope names a component, not a location. See CLAUDE.md > Commit scope."
fi

repo_path=$(git rev-parse --show-toplevel 2>/dev/null || true)
repo_key=${repo_path//[^a-zA-Z0-9_]/_}
cache_dir="${XDG_RUNTIME_DIR:-$HOME/.cache/claude}"
mkdir -p "$cache_dir" 2>/dev/null || true
scope_cache="${cache_dir}/commit-scopes-${repo_key}"
scope_age=999
if [[ -f "$scope_cache" ]]; then
  scope_age=$((EPOCHSECONDS - $(file_mtime "$scope_cache")))
fi
if ((scope_age > 60)); then
  known_scopes=$(git log --format='%s' -50 2>/dev/null \
    | awk -F'[()]' '/^[a-z]+\(/ && !seen[$2]++ { s = s (s?",":"") $2 } END { print s }' || true)
  printf '%s' "$known_scopes" >"$scope_cache" 2>/dev/null || true
else
  known_scopes=$(cat "$scope_cache" 2>/dev/null || true)
fi

# Build context string for structured injection.
suggested=$(suggest_scope "$staged")
top_level_count=$(echo "$staged" | grep '/' | cut -d/ -f1 | sort -u | wc -l | tr -d ' ')

ctx="Staged files (${file_count}): ${staged}"
if [[ -n "$dirs" ]]; then
  ctx+=". Top-level directories: ${dirs}"
fi
if [[ -n "$known_scopes" ]]; then
  ctx+=". Known scopes: ${known_scopes}"
fi
if [[ -n "$suggested" ]]; then
  ctx+=". Suggested scope (derived): ${suggested}"
fi
if ((top_level_count > 1)); then
  ctx+=". ATOMICITY: staged files span ${top_level_count} top-level dirs. Verify ONE logical change; split if not."
fi

# S4: new-scope soft advisory (declared scope valid but unfamiliar)
if [[ -n "${declared_scope:-}" ]] \
  && ! is_banned_scope "$declared_scope" "$staged" \
  && ! echo "$known_scopes" | tr ',' '\n' | grep -qxF "$declared_scope" \
  && [[ "$declared_scope" != "$suggested" ]]; then
  ctx+=". NEW SCOPE: '${declared_scope}' not in git log history; suggested from paths is '${suggested:-<none>}'. Verify scope names a component."
fi

ctx+=". Pick scope by component, not artifact path. See CLAUDE.md > Commit scope."

emit_context "PreToolUse" "$ctx"

exit 0
