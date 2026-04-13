---
description: GitHub Actions conventions -- SHA pinning, permissions, OIDC auth
paths:
  - ".github/**"
globs: true
---

# GitHub Actions

- Pin actions by full commit SHA, not tag: `actions/checkout@<sha>` not `@v4`
- Always declare a `permissions:` block at job level with least privilege -- omitting defaults to broad access
- Use OIDC (`id-token: write`) for cloud auth instead of long-lived credential secrets
- Guard comment-triggered workflows against self-triggers: `if: github.actor != 'claude[bot]'`
