---
description: "Review all worktree changes iteratively, then create a PR"
argument-hint: "[--max-iterations N] [--force]"
---

# Pre-PR Review & Create

Execute the setup script to initialize the review loop:

```!
"${CLAUDE_PLUGIN_ROOT}/skills/create/scripts/setup.sh" $ARGUMENTS
```

Begin the review process now. Follow the instructions from the Ralph loop prompt above.

CRITICAL RULE: Only output `<promise>PR_CREATED</promise>` when ALL review passes are genuinely clean AND the PR has been successfully created. Do not output false promises to escape the loop.
