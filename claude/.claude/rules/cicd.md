# CI/CD

- Never merge to main without a passing pipeline; treat a red pipeline as a blocker
- Keep pipelines fast: split slow steps into separate jobs, cache dependency installs keyed on lockfile hash
- Pipelines are code: version-control workflow files, use reusable workflows/templates to avoid duplication
- Secrets in CI must use the platform's secret store -- never pass them as plain environment variables in logs
- Pin action/orb/plugin versions by commit SHA, not tag, to prevent supply-chain drift
- Fail fast: put lint and unit tests first, expensive integration tests last
