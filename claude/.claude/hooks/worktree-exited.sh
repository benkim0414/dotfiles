#!/usr/bin/env bash
# PostToolUse hook (matcher: ExitWorktree):
# Remind Claude of the required PR workflow after leaving the worktree.
# Stdout is added to Claude's context. Never exit non-zero (PostToolUse should not block).
set -euo pipefail

cat <<'EOF'
[git-workflow] Worktree exited. You are back on the main branch.
[git-workflow] REQUIRED next steps (in order):
[git-workflow]   1. If not already done from within the worktree:
[git-workflow]        git push origin <your-feature-branch>
[git-workflow]        gh pr create
[git-workflow]   2. STOP — wait for the user to review and approve the PR on GitHub.
[git-workflow]   3. Do NOT run 'gh pr merge' without explicit user approval.
[git-workflow]   4. After the user merges: run 'git pull' to update local main.
EOF
