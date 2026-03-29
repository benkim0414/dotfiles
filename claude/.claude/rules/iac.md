# Infrastructure as Code & GitOps

- All infra changes go through version control; no manual changes that bypass the repo
- Idempotent by default: applying the same config twice must be safe
- Declarative over imperative; describe desired state, let systems reconcile
- Pin versions: chart versions, image tags/digests, tool versions -- avoid floating refs
- Validate before apply: use dry-run, diff, or plan output before making changes
- Document why decisions were made, not just what the config does
- Git is the single source of truth; out-of-band changes will be overwritten by reconciliation
- Never mutate controller-managed resources directly; patch the repo instead
- Review resource diffs before syncing; investigate drift before applying
- Secrets in GitOps repos must be encrypted -- never commit plaintext Secret manifests
- Break large changes into smaller PRs; one logical change per PR where reasonable
