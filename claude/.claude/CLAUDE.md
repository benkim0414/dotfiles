# Global Claude Code Preferences

## Claude Code Workflow
- Always invoke sequential-thinking MCP before implementing non-trivial changes
- Ask for explicit confirmation before destructive operations (deletes, force-pushes, infrastructure-level changes)
- Read existing code and configs before proposing changes; understand before modifying
- Prefer targeted edits over full file rewrites
- Never use emojis in responses
- Editor: nvim

## Git Discipline
- Conventional commits: `type(scope): description` — types: feat, fix, docs, chore, refactor, test, ci, perf
- Atomic commits: one logical change per commit; keep unrelated changes separate
- Write a commit body when the why is not obvious from the title
- Branch workflow: feature branches off main, open PR
- Never force-push to main or shared branches
- Review diffs for accidental secrets before every commit

## Security
- Never hardcode secrets, tokens, or credentials in version-controlled files
- Rotate secrets immediately after accidental exposure; deleting commits is insufficient
- Least privilege: grant only the permissions actually needed
- Prefer dedicated secret management tools over environment variables or config files
- Audit new tool installations and third-party scripts before running them

## Infrastructure as Code
- All infra changes go through version control; no manual changes that bypass the repo
- Idempotent by default: applying the same config twice must be safe
- Declarative over imperative; describe desired state, let systems reconcile
- Pin versions: chart versions, image tags/digests, tool versions — avoid floating refs
- Validate before apply: use dry-run, diff, or plan output before making changes
- Document why decisions were made, not just what the config does

## Kubernetes and Containers
- Always set resource requests and limits on every container
- Use readiness and liveness probes on every workload
- Pin image tags — never use `:latest` in committed manifests
- Label every resource consistently: app, component, version
- Use namespaces for isolation; avoid the default namespace for workloads
- Run containers as non-root; drop unnecessary Linux capabilities
- Prefer minimal base images (distroless, alpine) to reduce attack surface

## GitOps
- Git is the single source of truth; out-of-band changes will be overwritten by reconciliation
- Never mutate controller-managed resources directly; patch the repo instead
- Review resource diffs before syncing; investigate drift before applying
- Secrets in GitOps repos must be encrypted — never commit plaintext Secret manifests
- Break large changes into smaller PRs; one logical change per PR where reasonable

## Observability
- Structured logs (JSON preferred); always include relevant context (resource, namespace, request ID)
- Metrics: expose a `/metrics` endpoint; use consistent labels for cross-service dashboards
- Alert on symptoms (error rate, latency, SLO burn), not causes (high CPU, pod restarted)
- Validate deployments by inspecting metrics and logs, not just rollout status
- Every alert rule must have a corresponding runbook or investigation guide

## Shell Scripting
- Always start scripts with `#!/usr/bin/env bash` and `set -euo pipefail`
- Quote all variable expansions: `"$var"` not `$var`
- Use `[[ ]]` for conditionals and `local` for function-scoped variables
- Provide a usage/help message; exit 1 on invalid arguments
- Log messages to stderr (`>&2`); reserve stdout for pipeline-consumable data
- ShellCheck must pass with no warnings before committing any script
- Prefer clarity over cleverness; scripts are read under pressure during incidents

## DevOps Philosophy
- Make changes reversible before making them; design for rollback from the start
- Automate repetitive tasks; document manual procedures until automation exists
- Every alert that fires should result in a fix, tuning, or suppression — never ignore
- Reduce toil continuously; if you do something manually twice, automate it the third time
