---
description: "Review all worktree changes iteratively, then create a PR"
argument-hint: "[--max-iterations N]"
---

# Pre-PR Review Loop

Execute the setup script to initialize the review loop:

```!
"$HOME/.claude/scripts/setup-review-cl.sh" $ARGUMENTS
```

Begin the review process now. Follow the instructions from the Ralph loop prompt above.

CRITICAL RULE: Only output `<promise>PR_CREATED</promise>` when the review is genuinely clean AND the PR has been successfully created. Do not output false promises to escape the loop.
