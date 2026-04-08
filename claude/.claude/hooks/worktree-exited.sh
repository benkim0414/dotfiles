#!/usr/bin/env bash
# PostToolUse hook (matcher: ExitWorktree):
# Remind Claude of the required next steps after leaving the worktree.
# Stdout is added to Claude's context. Never exit non-zero (PostToolUse should not block).
set -euo pipefail

if [[ "${CLAUDE_GIT_WORKFLOW:-}" == "no-pr" ]]; then
  cat <<'EOF'
[git-workflow] Worktree exited. You are back on the main branch.
[git-workflow] Next steps:
[git-workflow]   1. Merge the feature branch: git merge <branch> --no-edit
[git-workflow]   2. Push to main: git push origin main
EOF
else
  cat <<'EOF'
[git-workflow] Worktree exited. You are back on the main branch.
[git-workflow] REQUIRED next steps (in order):
[git-workflow]   1. STOP — wait for the user to merge the PR on GitHub.
[git-workflow]   2. Do NOT run 'gh pr merge' without explicit user approval.
[git-workflow]   3. After the user merges: run '/merge-pr <number>' to merge, update local main,
[git-workflow]      and clean up the worktree and local branch automatically.
[git-workflow]      Or if the user merged via GitHub UI: run 'git pull' to update local main,
[git-workflow]      then 'git worktree remove <path>' and 'git branch -d <branch>' to clean up.
EOF
fi
