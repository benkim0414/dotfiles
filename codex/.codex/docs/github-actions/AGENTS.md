# GitHub Actions Guidance

Read this guide before touching GitHub Actions workflows or reusable actions.

- Pin actions by full commit SHA, not tag: `actions/checkout@<sha>`, not
  `@v4`.
- Always declare a job-level `permissions:` block with least privilege.
- Use OIDC with `id-token: write` for cloud auth instead of long-lived
  credential secrets.
- Guard comment-triggered workflows against self-triggers:
  `if: github.actor != 'claude[bot]'`.
