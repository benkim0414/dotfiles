---
name: rules-github-actions
description: >
  GitHub Actions security and convention rules: SHA pinning, least-privilege permissions,
  OIDC auth. Use when editing .github/workflows/*.yml or any file under .github/.
---

# GitHub Actions

- Pin actions by full commit SHA, not tag: `actions/checkout@<sha>` not `@v4`
- Always declare a `permissions:` block at job level with least privilege -- omitting defaults to broad access
- Use OIDC (`id-token: write`) for cloud auth instead of long-lived credential secrets
- Guard comment-triggered workflows against self-triggers: `if: github.actor != 'claude[bot]'`
