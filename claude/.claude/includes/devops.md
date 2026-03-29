# DevOps

## Kubernetes
- Always set resource requests and limits on every container
- Use readiness and liveness probes on every workload
- Pin image tags -- never use `:latest` in committed manifests
- Label every resource consistently: app, component, version
- Run containers as non-root; drop unnecessary Linux capabilities

## Infrastructure as Code
- Pin versions: chart versions, image tags/digests, tool versions -- avoid floating refs
- Never mutate controller-managed resources directly; patch the repo instead
- Secrets in GitOps repos must be encrypted -- never commit plaintext Secret manifests

## CI/CD
- Pin action/orb/plugin versions by commit SHA, not tag, to prevent supply-chain drift

## Shell
- ShellCheck must pass with no warnings before committing any script
