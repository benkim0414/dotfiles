#!/usr/bin/env bash
# PostToolUse hook (matcher: ExitWorktree):
# Remind Claude of the required PR workflow after leaving the worktree.
# Stdout is added to Claude's context. Never exit non-zero (PostToolUse should not block).
set -euo pipefail

cat <<'EOF'
[git-workflow] Worktree exited. You are back on the main branch.
[git-workflow] REQUIRED next steps (in order):
[git-workflow]   1. STOP — wait for the user to merge the PR on GitHub.
[git-workflow]   2. Do NOT run 'gh pr merge' without explicit user approval.
[git-workflow]   3. After the user merges: run 'git pull' to update local main.
EOF
