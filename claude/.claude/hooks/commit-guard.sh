#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): enforce atomic commits with correct scope.
# Blocks blanket staging. Injects staged files + known scopes at commit time.
# Exit 0 = allow (stdout → context). Exit 2 = block (stderr → Claude).
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

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
if echo "$COMMAND" | grep -qE 'git\s+commit\s+.*(-a\s|-a$|-am\s|--all)'; then
  echo "BLOCKED: Do not use 'git commit -a' — it bypasses selective staging." >&2
  echo "" >&2
  echo "  Stage specific files first, then commit:" >&2
  echo "    git add <file1> <file2>" >&2
  echo "    git commit -m \"type(scope): description\"" >&2
  exit 2
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

# Collect known scopes from recent history
known_scopes=$(git log --format='%s' -200 2>/dev/null \
  | sed -n 's/^[a-z]*(\([^)]*\)).*/\1/p' \
  | sort -u | tr '\n' ', ' | sed 's/,$//' || true)

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
